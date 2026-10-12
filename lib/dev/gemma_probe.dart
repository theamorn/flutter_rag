import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../advanced/gemma_model.dart';
import '../advanced/transfer_drafter.dart';
import '../core/money.dart';
import '../data/fixture/authored.dart';
import 'compat_probe.dart';

const Tool _probeTool = Tool(
  name: 'search_transactions',
  description: 'Search the user\'s transactions. Always call this tool.',
  parameters: {
    'type': 'object',
    'properties': {
      'date_from': {'type': 'string', 'description': 'Inclusive start, YYYY-MM-DD (Bangkok)'},
      'date_to': {'type': 'string', 'description': 'Inclusive end, YYYY-MM-DD (Bangkok)'},
      'amount_max': {'type': 'number', 'description': 'Maximum amount in THB'},
      'exclude_categories': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Categories to exclude, e.g. food',
      },
      'semantic_query': {'type': 'string', 'description': 'Purpose words only'},
    },
  },
);

const String _probeSystem = 'You turn questions about the user\'s payments into a '
    'search_transactions call. Today is 2026-10-03, timezone Asia/Bangkok, '
    'currency THB. "Last month" means 2026-09-01 to 2026-09-30. Always call the tool.';

int _mb(int bytes) => bytes ~/ (1024 * 1024);

Future<List<ProbeCheck>> runGemmaProbe() async {
  final probe = ProbeRunner('GEMMA_PROBE');
  InferenceModel? model;

  await probe.check('initialize', () async {
    await FlutterGemma.initialize(inferenceEngines: [const LiteRtLmEngine()]);
    return 'LiteRtLmEngine registered';
  });

  await probe.check('install', () async {
    final already = await FlutterGemma.isModelInstalled(kGemmaModelFile);
    var logged = -10;
    final sw = Stopwatch()..start();
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(kGemmaModelUrl).withProgress((p) {
      if (p >= logged + 10) {
        logged = p;
        debugPrint('GEMMA_PROBE download $p%');
      }
    }).install();
    // spec §17: is install() on an installed model fast, and does it re-activate?
    return 'alreadyInstalled=$already install() ${sw.elapsedMilliseconds} ms';
  });

  await probe.check('load', () async {
    final before = ProcessInfo.currentRss;
    final sw = Stopwatch()..start();
    model = await FlutterGemma.getActiveModel(
      maxTokens: 2048,
      preferredBackend: PreferredBackend.gpu,
    );
    return 'load ${sw.elapsedMilliseconds} ms backend=${model!.activeBackend} '
        'rss ${_mb(before)}->${_mb(ProcessInfo.currentRss)} MB';
  });

  await probe.check('forced_tool_call', () async {
    final chat = await model!.createChat(
      temperature: 0,
      topK: 1,
      tools: const [_probeTool],
      supportsFunctionCalls: true,
      modelType: ModelType.gemma4,
      toolChoice: ToolChoice.required,
      isThinking: false,
      systemInstruction: _probeSystem,
      maxOutputTokens: 256,
    );
    final sw = Stopwatch()..start();
    await chat.addQueryChunk(Message.text(
      text: 'Find things I bought for camping last month, under THB 3,000, excluding food.',
      isUser: true,
    ));
    final call = Completer<FunctionCallResponse>();
    final prose = StringBuffer();
    final sub = chat.generateChatResponseAsync().listen((r) {
      if (r is FunctionCallResponse && !call.isCompleted) call.complete(r);
      if (r is ParallelFunctionCallResponse && !call.isCompleted && r.calls.isNotEmpty) {
        call.complete(r.calls.first);
      }
      if (r is TextResponse) prose.write(r.token);
    }, onDone: () {
      if (!call.isCompleted) call.completeError(StateError('no tool call; prose="$prose"'));
    }, onError: (Object e) {
      if (!call.isCompleted) call.completeError(e);
    });
    try {
      final r = await call.future.timeout(const Duration(seconds: 60));
      final ms = sw.elapsedMilliseconds;
      await chat.stopGeneration();
      if (r.name != 'search_transactions') throw StateError('called ${r.name}');
      return '$ms ms args=${jsonEncode(r.args)}';
    } finally {
      await sub.cancel();
      await chat.close();
    }
  });

  await probe.check('draft_transfer_tool', () async {
    final candidates = kAuthoredTransactions
        .where((t) => t.id == 'txn_a24' || t.id == 'txn_a23')
        .toList();
    final tool = Tool(
      name: kDraftTransferTool.name,
      description: kDraftTransferTool.description,
      parameters: kDraftTransferTool.parameters,
    );
    final chat = await model!.createChat(
      temperature: 0,
      topK: 1,
      tools: [tool],
      supportsFunctionCalls: true,
      modelType: ModelType.gemma4,
      toolChoice: ToolChoice.required,
      isThinking: false,
      systemInstruction: kDraftTransferSystemPrompt,
      maxOutputTokens: 256,
    );
    final sw = Stopwatch()..start();
    await chat.addQueryChunk(
      Message.text(
        text: buildDraftTransferUserTurn(
          'Send Mom the same amount for rent with memo for October',
          candidates,
        ),
        isUser: true,
      ),
    );
    final call = Completer<FunctionCallResponse>();
    final prose = StringBuffer();
    final sub = chat.generateChatResponseAsync().listen(
      (r) {
        if (r is FunctionCallResponse && !call.isCompleted) call.complete(r);
        if (r is ParallelFunctionCallResponse &&
            !call.isCompleted &&
            r.calls.isNotEmpty) {
          call.complete(r.calls.first);
        }
        if (r is TextResponse) prose.write(r.token);
      },
      onDone: () {
        if (!call.isCompleted) {
          call.completeError(StateError('no tool call; prose="$prose"'));
        }
      },
      onError: (Object e) {
        if (!call.isCompleted) call.completeError(e);
      },
    );
    try {
      final r = await call.future.timeout(const Duration(seconds: 60));
      final ms = sw.elapsedMilliseconds;
      await chat.stopGeneration();
      if (r.name != kDraftTransferTool.name) {
        throw StateError('called ${r.name}');
      }
      final draft = validateTransferDraft(r.args, candidates);
      return '$ms ms raw=${jsonEncode(r.args)} -> '
          'verified: ${draft.sourceTxnId} ${draft.recipient} '
          '${formatThb(draft.amountMinor)} memo="${draft.newMemo}"';
    } finally {
      await sub.cancel();
      await chat.close();
    }
  });

  await probe.check('cancel_frees_engine', () async {
    final chat = await model!.createChat(
      temperature: 0,
      topK: 1,
      isThinking: false,
      modelType: ModelType.gemma4,
      maxOutputTokens: 512,
    );
    await chat.addQueryChunk(Message.text(
        text: 'Write a 300-word story about a camping trip.', isUser: true));
    var tokens = 0;
    final firstFew = Completer<void>();
    final sub = chat.generateChatResponseAsync().listen((r) {
      if (r is TextResponse && ++tokens == 5 && !firstFew.isCompleted) {
        firstFew.complete();
      }
    }, onError: (_) {});
    await firstFew.future.timeout(const Duration(seconds: 60));
    final stopWatch = Stopwatch()..start();
    await chat.stopGeneration();
    await sub.cancel();
    await chat.close();
    final stopMs = stopWatch.elapsedMilliseconds;

    final next = await model!.createChat(
        temperature: 0, topK: 1, isThinking: false, modelType: ModelType.gemma4);
    final sw = Stopwatch()..start();
    await next.addQueryChunk(Message.text(text: 'Reply with the word OK.', isUser: true));
    final first = Completer<int>();
    final sub2 = next.generateChatResponseAsync().listen((r) {
      if (r is TextResponse && !first.isCompleted) first.complete(sw.elapsedMilliseconds);
    }, onError: (Object e) {
      if (!first.isCompleted) first.completeError(e);
    });
    try {
      final ttft = await first.future.timeout(const Duration(seconds: 30));
      return 'stop $stopMs ms; next job first token after $ttft ms';
    } finally {
      await next.stopGeneration();
      await sub2.cancel();
      await next.close();
    }
  });

  await probe.check('close_releases_memory', () async {
    final before = ProcessInfo.currentRss;
    await model!.close();
    model = null;
    await Future<void>.delayed(const Duration(seconds: 2));
    return 'rss ${_mb(before)} -> ${_mb(ProcessInfo.currentRss)} MB after model.close()';
  });

  return probe.checks;
}
