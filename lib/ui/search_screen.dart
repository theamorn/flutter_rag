import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/bangkok_time.dart';
import '../core/transaction.dart';
import '../results/search_controller.dart';
import '../perf/timing_log.dart';
import 'timing_panel.dart';
import 'explanation_card.dart';
import 'transfer_draft_card.dart';
import 'notes_banner.dart';
import 'advanced_switch.dart';
import 'plan_chips.dart';
import 'search_field.dart';
import 'setup_screen.dart';
import 'slip_sheet.dart';
import 'summary_bar.dart';
import 'transaction_list.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  bool _showTimings = false;

  TransactionSearchController get _search => widget.services.search;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Transactions'),
            Text(
              'Demo date: ${formatBangkokDate(kReferenceNow)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Timings',
            icon: Icon(_showTimings ? Icons.speed : Icons.speed_outlined),
            onPressed: () => setState(() => _showTimings = !_showTimings),
          ),
          IconButton(
            tooltip: 'On-device models',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SetupScreen(services: widget.services),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_search, ?widget.services.advanced]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .65,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SearchField(
                        onSubmit: (q) =>
                            _search.submit(q, useAdvancedPlanner: false),
                        onClear: _search.browse,
                      ),
                      if (widget.services.advanced != null)
                        AdvancedSwitch(
                          controller: widget.services.advanced!,
                          onNeedsSetup: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  SetupScreen(services: widget.services),
                            ),
                          ),
                        ),
                      PlanChips(
                        plan: _search.plan,
                        onChanged: _search.applyPlan,
                      ),
                      NotesBanner(
                        notes: _search.plan.notes,
                        errors: _search.errors,
                        notice: _search.notice,
                      ),
                      if (_search.lastQuery != null)
                        SearchField(
                          key: const ValueKey('refine'),
                          hint: 'Refine: e.g. go back one year',
                          icon: Icons.subdirectory_arrow_right,
                          onSubmit: (q) =>
                              _search.refine(q, useAdvancedPlanner: false),
                        ),
                      SummaryBar(
                        summary: _search.summary,
                        busy:
                            _search.busy ||
                            _search.explaining ||
                            _search.draftingTransfer,
                        trailing:
                            (widget.services.advanced?.isOn ?? false) &&
                                _search.pager.items.isNotEmpty
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed:
                                        _search.explaining ||
                                            _search.draftingTransfer ||
                                            _search.busy
                                        ? null
                                        : _search.explain,
                                    icon: const Icon(Icons.auto_awesome),
                                    label: const Text('Explain results'),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  if (_search.canDraftTransfer)
                                    TextButton.icon(
                                      onPressed:
                                          _search.explaining ||
                                              _search.draftingTransfer ||
                                              _search.busy
                                          ? null
                                          : _onDraftTransferPressed,
                                      icon: const Icon(Icons.send_outlined),
                                      label: const Text('Draft transfer'),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                ],
                              )
                            : null,
                      ),
                      if (_search.explanation != null)
                        ExplanationCard(
                          key: ObjectKey(_search.explanation),
                          explanation: _search.explanation!,
                          onOpen: _openById,
                          onDismiss: _search.dismissExplanation,
                        ),
                      if (_search.transferDraft != null)
                        TransferDraftCard(
                          key: ObjectKey(_search.transferDraft),
                          draft: _search.transferDraft!,
                          onOpen: _openById,
                          onDismiss: _search.dismissTransferDraft,
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: TransactionList(pager: _search.pager, onOpen: _open),
              ),
              if (_showTimings)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .3,
                  ),
                  child: SingleChildScrollView(
                    child: TimingPanel(
                      log: widget.services.timingLog,
                      lastTimings: _search.lastTimings,
                      resources: () =>
                          ResourceSnapshot.capture(widget.services.dbPaths),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDraftTransferPressed() async {
    await _search.draftTransfer();
    final draft = _search.transferDraft;
    if (!mounted || draft == null) return;
    await showTransferDraftDialog(
      context,
      draft: draft,
      onOpen: _openById,
      onDismiss: _search.dismissTransferDraft,
    );
  }

  /// Opens the stored row, so the slip shows the current memo and fields.
  Future<void> _openById(String id) async {
    final Transaction? t;
    try {
      t = await widget.services.repo.getById(id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that transaction.')),
      );
      return;
    }
    if (t != null && mounted) _open(t);
  }

  void _open(Transaction t) => showTransactionSlip(
    context,
    transaction: t,
    onSaveMemo: _search.updateMemo,
  );
}
