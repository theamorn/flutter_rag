import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_rag/advanced/flutter_gemma_runtime.dart';
import 'package:flutter_rag/advanced/gemma_runtime.dart';
import 'package:flutter_rag/advanced/gemma_tool.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeModel implements InferenceModel {
  final events = <String>[];
  Completer<void>? createHold;
  late NativeChat nativeChat = NativeChat(events);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createChat) {
      events.add('create');
      expect(
        invocation.namedArguments[#supportsFunctionCalls],
        (invocation.namedArguments[#tools] as List).isNotEmpty,
      );
      expect(
        invocation.namedArguments[#toolChoice],
        (invocation.namedArguments[#tools] as List).isEmpty ? ToolChoice.auto : ToolChoice.required,
      );
      expect(invocation.namedArguments[#modelType], ModelType.gemma4);
      return () async {
        await createHold?.future;
        return nativeChat;
      }();
    }
    if (invocation.memberName == #close) {
      events.add('model.close');
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class NativeChat implements InferenceChat {
  NativeChat(this.events);
  final List<String> events;
  final stream = StreamController<ModelResponse>.broadcast();
  Completer<void>? queryHold, stopHold, closeHold;
  @override
  Future<void> addQueryChunk(Message message, [bool noTool = false, bool prefix = false]) async {
    events.add('query');
    await queryHold?.future;
  }

  @override
  Stream<ModelResponse> generateChatResponseAsync() {
    events.add('stream');
    return stream.stream;
  }

  @override
  Future<void> stopGeneration() async {
    events.add('stop');
    await stopHold?.future;
  }

  @override
  Future<void> close() async {
    events.add('close');
    await closeHold?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late NativeModel model;
  late FlutterGemmaRuntime runtime;
  Future<Map<String, dynamic>> call([Duration timeout = const Duration(seconds: 10)]) =>
      runtime.callTool(system: 'system', user: 'query', tool: kSearchTool, timeout: timeout);
  Future<void> turn() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    model = NativeModel();
    runtime = FlutterGemmaRuntime(modelLoader: () async => model);
    await runtime.load();
  });
  tearDown(() async {
    await runtime.unload();
    await model.nativeChat.stream.close();
  });

  test('matching parallel call stops, cancels subscription, closes before return', () async {
    final pending = call();
    await turn();
    model.nativeChat.stream.add(
      ParallelFunctionCallResponse(
        calls: [
          FunctionCallResponse(name: 'other', args: {}),
          FunctionCallResponse(
            name: kSearchTool.name,
            args: {
              'shops': ['7-11'],
            },
          ),
        ],
      ),
    );
    expect(await pending, {
      'shops': ['7-11'],
    });
    expect(model.events, ['create', 'query', 'stream', 'stop', 'close']);
    expect(model.nativeChat.stream.hasListener, isFalse);
  });
  test('cancel during create awaits returned chat cleanup and skips query', () async {
    model.createHold = Completer<void>();
    final pending = call();
    final checked = expectLater(pending, throwsA(isA<GemmaCancelled>()));
    await turn();
    var settled = false;
    final stopped = runtime.cancel().then((_) => settled = true);
    await turn();
    expect(settled, isFalse);
    model.createHold!.complete();
    await stopped;
    await checked;
    expect(model.events, ['create', 'stop', 'close']);
  });
  test('cancel during query waits for stop and close, never starts stream', () async {
    model.nativeChat.queryHold = Completer<void>();
    model.nativeChat.closeHold = Completer<void>();
    final pending = call();
    final checked = expectLater(pending, throwsA(isA<GemmaCancelled>()));
    await turn();
    var settled = false;
    final stopped = runtime.cancel().then((_) => settled = true);
    await turn();
    expect(model.events, ['create', 'query', 'stop']);
    model.nativeChat.queryHold!.complete();
    await turn();
    expect(settled, isFalse);
    model.nativeChat.closeHold!.complete();
    await stopped;
    await checked;
    expect(model.events.contains('stream'), isFalse);
  });
  test('deadline includes create await, closes late chat before timeout returns', () async {
    model.createHold = Completer<void>();
    final pending = call(const Duration(milliseconds: 5));
    final checked = expectLater(pending, throwsA(isA<GemmaTimeout>()));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    model.createHold!.complete();
    await checked;
    expect(model.events, ['create', 'stop', 'close']);
  });
  test('stream timeout waits native stop before next conversation', () async {
    model.nativeChat.stopHold = Completer<void>();
    final pending = call(const Duration(milliseconds: 5));
    var settled = false;
    final checked = expectLater(pending, throwsA(isA<GemmaTimeout>())).then((_) => settled = true);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(settled, isFalse);
    expect(model.events.last, 'stop');
    model.nativeChat.stopHold!.complete();
    await checked;
    model.nativeChat = NativeChat(model.events);
    final next = call();
    await turn();
    model.nativeChat.stream.add(FunctionCallResponse(name: kSearchTool.name, args: {}));
    await next;
    expect(model.events.where((e) => e == 'close').length, 2);
  });
  test('stream errors still stop and close', () async {
    final pending = call();
    final checked = expectLater(pending, throwsStateError);
    await turn();
    model.nativeChat.stream.addError(StateError('native failure'));
    await checked;
    expect(model.events.sublist(3), ['stop', 'close']);
  });
  test('unknown call and prose never become a plan', () async {
    final pending = call();
    final checked = expectLater(pending, throwsA(isA<GemmaNoToolCall>()));
    await turn();
    model.nativeChat.stream.add(FunctionCallResponse(name: 'other', args: {}));
    model.nativeChat.stream.add(TextResponse('hello'));
    await model.nativeChat.stream.close();
    await checked;
  });
  test('query await is included in deadline and cannot start late decoding', () async {
    model.nativeChat.queryHold = Completer<void>();
    final pending = call(const Duration(milliseconds: 5));
    final checked = expectLater(pending, throwsA(isA<GemmaTimeout>()));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(model.events, ['create', 'query', 'stop']);
    model.nativeChat.queryHold!.complete();
    await checked;
    expect(model.events, ['create', 'query', 'stop', 'close']);
  });
  test('explanation streams text without tool declarations and closes', () async {
    final pending = runtime.generate(
      system: 'system',
      user: 'query',
      timeout: const Duration(seconds: 10),
    );
    await turn();
    model.nativeChat.stream.add(const TextResponse('Hello'));
    model.nativeChat.stream.add(const TextResponse(' world'));
    await model.nativeChat.stream.close();
    expect(await pending, 'Hello world');
    expect(model.events, ['create', 'query', 'stream', 'stop', 'close']);
  });
}
