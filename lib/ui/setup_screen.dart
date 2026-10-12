import 'package:flutter/material.dart';

import '../app_services.dart';
import 'gemma_setup_card.dart';
import '../retrieval/index_manager.dart';
import '../search/mlkit_entity_source.dart';

/// Readiness of every on-device model (spec §11 SetupScreen). Task 22 adds
/// the Gemma card.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool? _entityReady;
  bool _downloading = false;
  String? _entityError;

  @override
  void initState() {
    super.initState();
    _checkEntityModel();
  }

  Future<void> _checkEntityModel() async {
    try {
      final ready = await MlKitEntitySource.isModelReady();
      if (mounted) setState(() => _entityReady = ready);
    } catch (e) {
      if (mounted) setState(() => _entityError = '$e');
    }
  }

  Future<void> _downloadEntityModel() async {
    setState(() {
      _downloading = true;
      _entityError = null;
    });
    try {
      final ok = await MlKitEntitySource.downloadModel();
      if (mounted) setState(() => _entityReady = ok);
    } catch (e) {
      if (mounted) setState(() => _entityError = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.services.index;
    return Scaffold(
      appBar: AppBar(title: const Text('On-device models')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('English entity model (ML Kit)'),
              subtitle: Text(
                _entityError ??
                    switch (_entityReady) {
                      null => 'Checking…',
                      true => 'Ready',
                      false => 'Not downloaded (needs network once)',
                    },
              ),
              trailing: _entityReady == false
                  ? (_downloading
                        ? const CircularProgressIndicator()
                        : FilledButton(
                            onPressed: _downloadEntityModel,
                            child: const Text('Download'),
                          ))
                  : null,
            ),
          ),
          if (index != null)
            ValueListenableBuilder<IndexProgress>(
              valueListenable: index.progress,
              builder: (context, p, _) => Card(
                child: ListTile(
                  leading: const Icon(Icons.manage_search),
                  title: const Text('Search index (MiniLM)'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (p.phase) {
                        IndexPhase.idle => 'Waiting',
                        IndexPhase.reconciling => 'Checking existing index…',
                        IndexPhase.indexing => 'Indexing ${p.done} / ${p.total}',
                        IndexPhase.ready =>
                          'Ready: ${p.total} transactions '
                              '(${(p.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s this launch)',
                        IndexPhase.failed => 'Failed: ${p.error}',
                      }),
                      if (p.phase == IndexPhase.indexing && p.total > 0)
                        LinearProgressIndicator(value: p.done / p.total),
                    ],
                  ),
                  trailing: p.phase == IndexPhase.failed
                      ? TextButton(onPressed: index.ensureIndexed, child: const Text('Retry'))
                      : null,
                ),
              ),
            ),
          if (widget.services.advanced != null)
            GemmaSetupCard(controller: widget.services.advanced!),
        ],
      ),
    );
  }
}
