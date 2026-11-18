import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/youtube_route_status.dart';
import 'package:flutter/widgets.dart';

class WdttStatusPanel extends StatelessWidget {
  const WdttStatusPanel({super.key, required this.status});

  final Map<Object?, Object?> status;

  String _message(AppLocalizations l10n, Object? phase) => switch (phase) {
    'backup' || 'recovering' => l10n.wdttUnavailable,
    'manualWdtt' => l10n.wdttManual,
    'manualVless' => l10n.wdttManualVless,
    'primary' => l10n.wdttPrimary,
    'starting' => l10n.wdttStartingBackup,
    'startingManual' => l10n.wdttStartingManual,
    'offline' => l10n.wdttOffline,
    'error' => l10n.wdttCheckError,
    _ => l10n.wdttChecking,
  };

  String _time(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds).showFull;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final phase = status['phase'];
    final switchedAt = status['switchedAt'] as int?;
    final events = (status['events'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Text(
          _message(l10n, phase),
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
        if (status['youtube'] case final Map snapshot)
          YouTubeRouteStatus(status: snapshot),
        if (switchedAt != null && status['route'] != null)
          Text(l10n.wdttSwitchedAt(_time(switchedAt))),
        Text(switch (phase) {
          'backup' => l10n.wdttRecoveryWaiting,
          'recovering' => l10n.wdttRecoveryConfirming,
          'manualWdtt' ||
          'manualVless' ||
          'startingManual' => l10n.wdttRecoveryManual,
          'primary' => l10n.wdttRecoveryReady,
          'offline' => l10n.wdttRecoveryOffline,
          'error' => l10n.wdttCheckError,
          _ => l10n.wdttChecking,
        }),
        if (events.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => dialogs.showCommonDialog<void>(
                context: context,
                child: AlertDialog(
                  title: l10n.wdttHistory,
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.close),
                    ),
                  ],
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        for (final event in events.cast<Map>())
                          Text(
                            '${_time(event['time'] as int)}\n'
                            '${event['phase'] == 'recovering' ? l10n.wdttRecoveryConfirming : _message(l10n, event['phase'])}',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              child: Text(l10n.wdttHistory),
            ),
          ),
      ],
    );
  }
}
