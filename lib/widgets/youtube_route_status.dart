import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';

class YouTubeRouteStatus extends StatelessWidget {
  const YouTubeRouteStatus({super.key, required this.status});

  final Map<Object?, Object?>? status;

  String _route(BuildContext context, Object? route) => switch (route) {
    'ByeDPI' => 'ByeDPI',
    'VLESS' => 'VLESS (VPS)',
    'WDTT' => 'WDTT (VPS)',
    'DIRECT' => 'DIRECT',
    _ => context.appLocalizations.byeDpiRouteUnknown,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final connections = (status?['connections'] as List? ?? const [])
        .cast<Map>();
    final routes = connections.map((c) => _route(context, c['route'])).toSet();
    final summary = connections.isEmpty
        ? '${l.byeDpiNextRoute} · ${_route(context, status?['next'])}'
        : routes.join(' + ');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        onPressed: () => dialogs.showCommonDialog<void>(
          context: context,
          child: AlertDialog(
            title: l.byeDpiActualRoute,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.close),
              ),
            ],
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(
                    '${l.byeDpiNextRoute} · ${_route(context, status?['next'])}',
                  ),
                  Text(l.byeDpiRouteScope),
                  if (connections.isEmpty) Text(l.byeDpiNoConnections),
                  for (final connection in connections)
                    Text(
                      '${connection['video'] == true ? l.byeDpiVideoTraffic : 'YouTube'} · ${_route(context, connection['route'])}\n'
                      '${connection['host']} · ${(connection['download'] as int).traffic.show}',
                    ),
                ],
              ),
            ),
          ),
        ),
        child: Text('YouTube · $summary'),
      ),
    );
  }
}
