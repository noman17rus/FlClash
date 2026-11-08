import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import 'card.dart';

Glyph _glyphOf(Mode mode) => switch (mode) {
  Mode.rule => AppGlyphs.rules,
  Mode.global => AppGlyphs.proxies,
  Mode.direct => AppGlyphs.target,
};

void _changeMode(WidgetRef ref, Mode mode) {
  if (ref.read(patchClashConfigProvider).mode == mode) return;
  ref.read(setupActionProvider.notifier).changeMode(mode);
}

class OutboundModeCard extends ConsumerWidget {
  const OutboundModeCard({super.key});

  static const _outer = 26.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wdttProfile = _wdttProfileId(ref);
    if (wdttProfile != null) {
      return _WdttRouteCard(key: ValueKey(wdttProfile), profileId: wdttProfile);
    }
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final tone = DashboardColors.of(context).tone;
    final style = AppTextStyle.footnote.of(context, emphasized: true);
    return DashboardCard(
      semanticLabel: context.appLocalizations.outboundMode,
      child: Column(
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.split,
            title: context.appLocalizations.outboundMode,
          ),
          const SizedBox(height: 12),
          DashboardConnectedGroup(
            children: [
              for (final (index, item) in Mode.values.indexed)
                Expanded(
                  child: DashboardConnectedButton(
                    selected: item == mode,
                    first: index == 0,
                    last: index == Mode.values.length - 1,
                    outer: _outer,
                    inner: 12,
                    background: tone,
                    semanticLabel: item.label,
                    onTap: () => _changeMode(ref, item),
                    builder: (foreground) => SizedBox(
                      height: 52,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 2,
                        children: [
                          GlyphIcon(
                            _glyphOf(item),
                            size: 18,
                            color: foreground,
                          ),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: foreground),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The desktop control row's mode switch; its buttons sit as far in from the
/// card's ends as from its edges so their corners stay concentric.
class OutboundModeBar extends ConsumerWidget {
  const OutboundModeBar({super.key});

  static const _inset = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wdttProfile = _wdttProfileId(ref);
    if (wdttProfile != null) {
      return _WdttRouteCard(
        key: ValueKey(wdttProfile),
        profileId: wdttProfile,
        compact: true,
      );
    }
    final density = DashboardDensityScope.of(context);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final appLocalizations = context.appLocalizations;
    final outer = dashboardCardRadius(density) - _inset;
    final style = AppTextStyle.subheadline.of(context, emphasized: true);
    return DashboardCard(
      semanticLabel: appLocalizations.outboundMode,
      padding: EdgeInsetsDirectional.fromSTEB(
        dashboardCardPadding(density).left,
        _inset,
        _inset,
        _inset,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: 16,
          children: [
            GlyphIcon(
              AppGlyphs.split,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 4),
              child: Text(
                appLocalizations.outboundMode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.cardTitle(context),
              ),
            ),
            Expanded(
              child: DashboardConnectedGroup(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, item) in Mode.values.indexed)
                    Expanded(
                      child: DashboardConnectedButton(
                        selected: item == mode,
                        first: index == 0,
                        last: index == Mode.values.length - 1,
                        outer: outer,
                        inner: 10,
                        background: DashboardColors.of(context).tone,
                        semanticLabel: item.label,
                        onTap: () => _changeMode(ref, item),
                        builder: (foreground) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 6,
                          children: [
                            GlyphIcon(
                              _glyphOf(item),
                              size: 18,
                              color: foreground,
                            ),
                            Flexible(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style.copyWith(color: foreground),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int? _wdttProfileId(WidgetRef ref) => system.isAndroid
    ? ref.watch(
        currentProfileProvider.select((profile) {
          return profile?.overrides.wdttFallbackLink.isWdttLink == true
              ? profile?.id
              : null;
        }),
      )
    : null;

class _WdttRouteCard extends ConsumerStatefulWidget {
  const _WdttRouteCard({
    super.key,
    required this.profileId,
    this.compact = false,
  });

  final int profileId;
  final bool compact;

  @override
  ConsumerState<_WdttRouteCard> createState() => _WdttRouteCardState();
}

class _WdttRouteCardState extends ConsumerState<_WdttRouteCard> {
  static final _vlessExit = RegExp(r'^"(?:[^"\\]|\\.)*" Vless ');
  late final OutboundIpProbe _probe;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (ref.read(appVisibleProvider) &&
          ref.read(isStartProvider) &&
          !ref.read(suspendProvider)) {
        _probe.refresh(const [routedOutbound]);
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.profileId;
    final group = wdttRouteGroupName(id);
    final selected =
        ref.watch(
          currentProfileProvider.select(
            (profile) => profile?.selectedMap[group],
          ),
        ) ??
        WdttRouteMode.automatic.proxyName(id);
    final active = ref.watch(isStartProvider) && !ref.watch(suspendProvider);
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final route = ref.watch(routeTrackerProvider);
    final stamp = entry.stamp;
    final exits =
        active &&
            entry.value != null &&
            stamp != null &&
            stamp.proxied &&
            route.isFresh(stamp)
        ? stamp.hits.map((hit) => hit.exit)
        : const <String>[];
    final l10n = context.appLocalizations;
    final (status, tone) = !active
        ? (l10n.notRunning, DashboardChipTone.idle)
        : exits.any(
            (exit) => exit.startsWith(
              '"${WdttRouteMode.wdtt.proxyName(id)}" Socks5 ',
            ),
          )
        ? ('WDTT', DashboardChipTone.ok)
        : exits.any(_vlessExit.hasMatch)
        ? ('VLESS', DashboardChipTone.ok)
        : exits.any((exit) => exit.startsWith('"DIRECT" Direct '))
        ? (l10n.direct, DashboardChipTone.warn)
        : entry.phase == ProbePhase.failed
        ? (l10n.serviceUnavailable, DashboardChipTone.warn)
        : (l10n.loading, DashboardChipTone.idle);
    final style = AppTextStyle.footnote.of(context, emphasized: true);
    final indicator = DashboardChip(label: status, tone: tone);
    final controls = DashboardConnectedGroup(
      children: [
        for (final (index, mode) in WdttRouteMode.values.indexed)
          Expanded(
            child: DashboardConnectedButton(
              selected: selected == mode.proxyName(id),
              first: index == 0,
              last: index == WdttRouteMode.values.length - 1,
              outer: OutboundModeCard._outer,
              inner: 12,
              background: DashboardColors.of(context).tone,
              semanticLabel: _label(mode, l10n.auto),
              onTap: () => ref
                  .read(proxiesActionProvider.notifier)
                  .changeProxyDebounce(group, mode.proxyName(id)),
              builder: (color) => SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    _label(mode, l10n.auto),
                    style: style.copyWith(color: color),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return DashboardCard(
      semanticLabel: l10n.outboundMode,
      padding: widget.compact ? const EdgeInsets.all(8) : null,
      child: widget.compact
          ? Row(
              spacing: 8,
              children: [
                indicator,
                Expanded(child: controls),
              ],
            )
          : Column(
              spacing: 12,
              children: [
                DashboardCardHeader(
                  glyph: AppGlyphs.split,
                  title: l10n.outboundMode,
                  leading: [indicator],
                ),
                controls,
              ],
            ),
    );
  }

  String _label(WdttRouteMode mode, String auto) => switch (mode) {
    WdttRouteMode.automatic => auto,
    WdttRouteMode.vless => 'VLESS',
    WdttRouteMode.wdtt => 'WDTT',
  };
}
