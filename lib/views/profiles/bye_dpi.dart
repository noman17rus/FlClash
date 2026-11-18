import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/youtube_route_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class ByeDpiView extends StatefulWidget {
  const ByeDpiView({super.key, required this.selected});

  final String selected;

  @override
  State<ByeDpiView> createState() => _ByeDpiViewState();
}

class _ByeDpiViewState extends State<ByeDpiView> {
  final _service = Service();
  final _results = <String, Map<String, Object?>>{};
  List<String> _catalog = [];
  late String _selected = widget.selected;
  DateTime? _updated;
  String? _error;
  bool _loading = true;
  bool _validating = false;
  bool _scanning = false;
  int _generation = 0;
  String? _testing;
  Map<Object?, Object?>? _routes;
  Timer? _routeTimer;
  bool _loadingRoutes = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadRoutes());
    _routeTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadRoutes(),
    );
  }

  Future<void> _loadRoutes() async {
    if (_loadingRoutes) return;
    _loadingRoutes = true;
    try {
      final routes = await _service.byeDpiRoutes();
      if (mounted) setState(() => _routes = routes);
    } catch (_) {
      if (mounted) setState(() => _routes = null);
    } finally {
      _loadingRoutes = false;
    }
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.byeDpiCatalog(refresh: refresh);
      if (!mounted) return;
      _showCatalog(snapshot);
      if (!refresh) {
        final fresh = await _service.byeDpiCatalog(
          refresh: true,
          automatic: true,
        );
        if (mounted) _showCatalog(fresh);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.appLocalizations.byeDpiCatalogError);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCatalog(Map<Object?, Object?> snapshot) {
    final stamp = snapshot['updated'] as int;
    setState(() {
      _catalog = (snapshot['strategies'] as List).cast<String>();
      _updated = stamp == 0 ? null : DateTime.fromMillisecondsSinceEpoch(stamp);
    });
  }

  List<String> get _choices =>
      {_selected, widget.selected, ..._catalog}.toList();

  int _compare(String a, String b) {
    final youtube = (_results[b]?['YouTube'] != null ? 1 : 0).compareTo(
      _results[a]?['YouTube'] != null ? 1 : 0,
    );
    if (youtube != 0) return youtube;
    final first = [
      'Google',
      'YouTube',
    ].map((key) => _results[a]?[key] as int?).nonNulls.toList();
    final second = [
      'Google',
      'YouTube',
    ].map((key) => _results[b]?[key] as int?).nonNulls.toList();
    final successes = second.length.compareTo(first.length);
    if (successes != 0) return successes;
    return first
        .fold<int>(0, (x, y) => x + y)
        .compareTo(second.fold<int>(0, (x, y) => x + y));
  }

  Future<void> _scan() async {
    final generation = ++_generation;
    final choices = _choices;
    setState(() {
      _results.clear();
      _scanning = true;
      _error = null;
    });
    bool current() => mounted && _generation == generation;
    try {
      final revision = await _service.byeDpiNetwork();
      for (final line in choices) {
        if (!current()) return;
        setState(() => _testing = line);
        Map<String, Object?> result;
        try {
          result = await _service.probeByeDpi(line, revision);
        } on PlatformException catch (e) {
          if (e.code != 'BYEDPI') rethrow;
          result = {'Google': null, 'YouTube': null};
        }
        if (!current()) return;
        setState(() => _results[line] = result);
      }
      if (current()) {
        final best = (choices..sort(_compare)).first;
        if (_results[best]?['YouTube'] != null) {
          setState(() => _selected = best);
        }
      }
    } on PlatformException catch (e) {
      if (current()) {
        setState(() {
          if (e.code == 'NETWORK_CHANGED') _results.clear();
          _error = e.code == 'NETWORK_CHANGED'
              ? context.appLocalizations.byeDpiNetworkChanged
              : e.message;
        });
      }
    } finally {
      if (current()) {
        setState(() {
          _scanning = false;
          _testing = null;
        });
      }
    }
  }

  void _cancel() {
    ++_generation;
    unawaited(_service.cancelByeDpiProbe());
    setState(() {
      _scanning = false;
      _testing = null;
    });
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    ++_generation;
    if (_scanning) unawaited(_service.cancelByeDpiProbe());
    super.dispose();
  }

  Future<void> _custom() async {
    final value = await dialogs.showCommonDialog<String>(
      child: InputDialog(
        title: context.appLocalizations.custom,
        value: _selected,
        maxLength: 4096,
      ),
    );
    if (value != null && value.trim().isNotEmpty && mounted) {
      setState(() => _selected = value.trim());
    }
  }

  Future<void> _apply() async {
    setState(() {
      _validating = true;
      _error = null;
    });
    try {
      await _service.validateByeDpi(_selected);
      if (mounted) Navigator.of(context).pop(_selected);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? context.appLocalizations.error);
      }
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final choices = _choices;
    final order = {for (final (index, line) in choices.indexed) line: index};
    choices.sort((a, b) {
      final score = _compare(a, b);
      return score == 0 ? order[a]!.compareTo(order[b]!) : score;
    });
    final busy = _scanning || _validating;
    final date = _updated?.toLocal().toString().split('.').first;
    final actions = [
      YouTubeRouteStatus(status: _routes),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FilledButton.icon(
          icon: GlyphIcon(
            _scanning ? AppGlyphs.close : AppGlyphs.sparkle,
            fill: 1,
          ),
          label: Text(_scanning ? l.cancel : l.byeDpiAutoSelect),
          onPressed: _scanning
              ? _cancel
              : _loading || _validating
              ? null
              : _scan,
        ),
      ),
      if (_scanning || _results.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${_results.length} / ${choices.length} · ${l.byeDpiYouTubeAvailable} · ${_results.values.where((r) => r['YouTube'] != null).length}',
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(l.byeDpiProbeScope, style: context.listCaptionStyle),
      ),
      Text(l.byeDpiAddress),
      if (_error != null) Text(_error!),
      ListItem(
        title: Text(l.byeDpiUpdate),
        subtitle: Text('${l.lastUpdated} · ${date ?? '—'}'),
        onTap: busy || _loading ? null : () => _load(refresh: true),
      ),
      ListItem(title: Text(l.custom), onTap: busy ? null : _custom),
      ListItem(
        title: Text(l.applyNow),
        subtitle: Text(_selected),
        onTap: busy ? null : _apply,
      ),
    ];
    return BaseScaffold(
      title: l.byeDpiChoose,
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          16,
          context.sectionsTopPadding,
          16,
          16 + context.bottomInset,
        ),
        itemCount: actions.length + choices.length,
        itemBuilder: (context, index) {
          if (index < actions.length) return actions[index];
          final line = choices[index - actions.length];
          final result = _results[line];
          final number = _catalog.indexOf(line) + 1;
          final youtube = result?['YouTube'];
          final checking = _testing == line;
          final status = checking
              ? l.byeDpiChecking
              : youtube != null
              ? '${l.byeDpiYouTubeAvailable} · $youtube ms'
              : result == null
              ? l.byeDpiNotTested
              : l.byeDpiYouTubeUnconfirmed;
          final statusColor = youtube != null
              ? context.colorScheme.success
              : result != null
              ? context.colorScheme.warning
              : context.colorScheme.onSurfaceVariant;
          return ListItem(
            leading: GlyphIcon(
              youtube != null
                  ? AppGlyphs.checkCircle
                  : result != null
                  ? AppGlyphs.warning
                  : AppGlyphs.clock,
              color: statusColor,
            ),
            title: Text(number == 0 ? l.custom : '${l.strategy} $number'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: context.listCaptionStyle.copyWith(color: statusColor),
                ),
                if (result != null)
                  Text(
                    'Google · ${result['Google'] == null ? l.byeDpiUnconfirmed : "${result['Google']} ms"}',
                  ),
                if (result?['YouTubeError'] case final String error)
                  Text(error, style: context.listCaptionStyle),
                Text(line, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
            trailing: _selected == line ? const SelectionCheck() : null,
            onTap: busy ? null : () => setState(() => _selected = line),
          );
        },
      ),
    );
  }
}
