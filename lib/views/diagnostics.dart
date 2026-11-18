import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/diagnostic_report.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiagnosticsView extends ConsumerStatefulWidget {
  const DiagnosticsView({super.key, this.runDiagnostics});

  final Future<Map<Object?, Object?>?> Function(int?, String?)? runDiagnostics;

  @override
  ConsumerState<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends ConsumerState<DiagnosticsView> {
  Map<String, String>? _results;
  bool _running = false;
  bool _exporting = false;
  bool _error = false;
  Timer? _timer;
  bool _polling = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || !_running) return;
    _polling = true;
    try {
      final results = await service?.getDiagnostics();
      if (mounted && _running && results?.isNotEmpty == true) {
        setState(() => _results = safeDiagnosticResults(results));
      }
    } on Exception {
      // The final response owns errors; polling only supplies progress.
    } finally {
      _polling = false;
    }
  }

  Future<void> _run() async {
    if (_running) return;
    final profile = ref.read(currentProfileProvider);
    final link = profile?.url.isWdttLink == true
        ? profile?.url
        : profile?.overrides.wdttFallbackLink;
    setState(() {
      _running = true;
      _error = false;
      _results = {for (final stage in diagnosticStages) stage: 'pending'};
    });
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
    try {
      final results = await (widget.runDiagnostics ?? service?.runDiagnostics)
          ?.call(profile?.id, link);
      if (mounted) setState(() => _results = safeDiagnosticResults(results));
    } on Exception {
      if (mounted) {
        setState(() {
          _error = true;
          _results = {
            for (final stage in diagnosticStages)
              stage: _results?[stage] == 'passed' ? 'passed' : 'unavailable',
          };
        });
      }
    } finally {
      _timer?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _export() async {
    if (_exporting || _running || _results == null) return;
    setState(() => _exporting = true);
    File? file;
    try {
      file = File('${await appPath.tempFilePath}.diagnostics.json');
      await file.safeWriteAsString(exportDiagnosticReport(_results!));
      await picker.saveFileWithPath('connection-diagnostics.json', file.path);
    } on Exception {
      if (mounted) setState(() => _error = true);
    } finally {
      try {
        if (file != null && await file.exists()) await file.delete();
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final labels = {
      'vless': 'VLESS',
      'turn': l10n.diagnosticTurn,
      'dtls': 'DTLS',
      'wireguard': 'WireGuard',
      'dns': 'DNS',
      'internet': l10n.diagnosticInternet,
    };
    final actions = {
      'vless': l10n.diagnosticVlessAction,
      'turn': l10n.diagnosticTurnAction,
      'dtls': l10n.diagnosticDtlsAction,
      'wireguard': l10n.diagnosticWireguardAction,
      'dns': l10n.diagnosticDnsAction,
      'internet': l10n.diagnosticInternetAction,
    };
    String status(String value) => switch (value) {
      'passed' => l10n.diagnosticPassed,
      'failed' || 'auth' => l10n.diagnosticFailed,
      'running' => l10n.diagnosticRunning,
      'pending' => l10n.diagnosticPending,
      'blocked' => l10n.diagnosticBlocked,
      'captcha' => l10n.diagnosticCaptcha,
      _ => l10n.diagnosticUnavailable,
    };
    return Scaffold(
      title: l10n.diagnostics,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Text(l10n.diagnosticScope),
            TextButton(
              key: ValueKey(_running),
              onPressed: _running ? null : _run,
              child: Text(
                _running ? l10n.diagnosticRunning : l10n.diagnosticStart,
              ),
            ),
            if (_error) Text(l10n.diagnosticError),
            if (_results != null) ...[
              for (final stage in diagnosticStages)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    Text(
                      '${labels[stage]} — ${status(_results![stage]!)}',
                      style: AppTextStyle.body.of(context, emphasized: true),
                    ),
                    if (_results![stage] == 'failed') Text(actions[stage]!),
                    if (_results![stage] == 'auth')
                      Text(l10n.diagnosticAuthAction),
                    if (_results![stage] == 'unavailable')
                      Text(l10n.diagnosticSetupAction),
                    if (_results![stage] == 'captcha')
                      Text(l10n.diagnosticCaptchaAction),
                  ],
                ),
              Text(l10n.diagnosticPrivacy),
              TextButton(
                key: ValueKey((_running, _exporting)),
                onPressed: _running || _exporting ? null : _export,
                child: Text(l10n.diagnosticExport),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
