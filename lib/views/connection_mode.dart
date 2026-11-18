import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/connection_mode.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';

class ConnectionModeView extends StatefulWidget {
  const ConnectionModeView({super.key, this.loadMode, this.saveMode});

  final Future<String?> Function()? loadMode;
  final Future<String?> Function(String)? saveMode;

  @override
  State<ConnectionModeView> createState() => _ConnectionModeViewState();
}

class _ConnectionModeViewState extends State<ConnectionModeView> {
  ConnectionMode? _mode;
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final name = await (widget.loadMode ?? service?.getConnectionMode)
          ?.call();
      final mode = ConnectionMode.values
          .where((mode) => mode.name == name)
          .firstOrNull;
      if (mode == null) throw StateError('Unknown connection mode');
      if (mounted) setState(() => _mode = mode);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(ConnectionMode mode) async {
    if (_busy || mode == _mode) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final saved = await (widget.saveMode ?? service?.setConnectionMode)?.call(
        mode.name,
      );
      if (saved != mode.name) throw StateError('Connection mode was not saved');
      if (mounted) setState(() => _mode = mode);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return BaseScaffold(
      title: l10n.connectionBalance,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.sectionsTopPadding,
          16,
          16 + context.bottomInset,
        ),
        children: [
          Text(l10n.connectionBalanceDescription),
          const SizedBox(height: 16),
          if (_busy) Text(l10n.loading),
          if (_error)
            ListItem(
              title: Text(l10n.connectionModeError),
              onTap: _busy ? null : _load,
            ),
          generateSection(
            items: [
              for (final mode in ConnectionMode.values)
                ListItem(
                  title: Text(mode.label),
                  subtitle: Text(mode.description),
                  trailing: _mode == mode ? const SelectionCheck() : null,
                  onTap: _busy || _mode == null ? null : () => _select(mode),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
