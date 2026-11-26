import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/help.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _SimpleState { noAccess, disconnected, connecting, protected, suspended }

class SimpleHomeView extends ConsumerWidget {
  const SimpleHomeView({super.key});

  _SimpleState _stateOf({
    required Profile? profile,
    required bool started,
    required bool suspended,
    required CoreStatus coreStatus,
  }) {
    if (profile == null) return _SimpleState.noAccess;
    if (suspended) return _SimpleState.suspended;
    if (!started) return _SimpleState.disconnected;
    if (coreStatus == CoreStatus.connected) return _SimpleState.protected;
    return _SimpleState.connecting;
  }

  ({String title, String body, Glyph glyph, Color color}) _contentOf(
    BuildContext context,
    _SimpleState state,
  ) {
    final l = context.appLocalizations;
    final colors = context.colorScheme;
    return switch (state) {
      _SimpleState.noAccess => (
        title: l.simpleNoAccessTitle,
        body: l.simpleNoAccessBody,
        glyph: AppGlyphs.key,
        color: colors.primary,
      ),
      _SimpleState.disconnected => (
        title: l.simpleDisconnectedTitle,
        body: l.simpleDisconnectedBody,
        glyph: AppGlyphs.lockOpen,
        color: colors.outline,
      ),
      _SimpleState.connecting => (
        title: l.simpleConnectingTitle,
        body: l.simpleConnectingBody,
        glyph: AppGlyphs.sync,
        color: colors.primary,
      ),
      _SimpleState.protected => (
        title: l.simpleProtectedTitle,
        body: l.simpleProtectedBody,
        glyph: AppGlyphs.lock,
        color: colors.primary,
      ),
      _SimpleState.suspended => (
        title: l.simpleSuspendedTitle,
        body: l.simpleSuspendedBody,
        glyph: AppGlyphs.lockOpen,
        color: colors.tertiary,
      ),
    };
  }

  Future<void> _addAccess(BuildContext context) async {
    await showFormSheet<Profile>(
      context: context,
      builder: (_) => const ManagedProfileForm(),
    );
  }

  void _toggle(WidgetRef ref, _SimpleState state) {
    if (state == _SimpleState.suspended) {
      unawaited(ref.read(setupActionProvider.notifier).setRunning(true));
      return;
    }
    ref.read(commonActionProvider.notifier).toggleRunning();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final profiles = ref.watch(profilesProvider);
    final profile = ref.watch(currentProfileProvider) ?? profiles.firstOrNull;
    final state = _stateOf(
      profile: profile,
      started: ref.watch(isStartProvider),
      suspended: ref.watch(suspendProvider),
      coreStatus: ref.watch(coreStatusProvider),
    );
    final content = _contentOf(context, state);
    final actionLabel = switch (state) {
      _SimpleState.noAccess => l.simpleAddAccess,
      _SimpleState.connecting => l.cancel,
      _SimpleState.suspended => l.simpleResume,
      _SimpleState.protected => l.simpleDisconnect,
      _ => l.simpleConnect,
    };
    return Scaffold(
      title: l.dashboard,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          context.sectionsTopPadding,
          20,
          28 + context.bottomInset,
        ),
        children: [
          _StatusCard(
            glyph: content.glyph,
            color: content.color,
            title: content.title,
            body: content.body,
            actionLabel: actionLabel,
            onPressed: state == _SimpleState.noAccess
                ? () => _addAccess(context)
                : () => _toggle(ref, state),
          ),
          if (profile == null) ...[
            const SizedBox(height: 12),
            generateSection(
              title: l.simpleHowTitle,
              items: [
                ListItem(
                  alignment: ListRowAlignment.top,
                  title: Text(l.simpleHowBody),
                ),
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.info),
                  title: Text(l.simpleHelp),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: () => BaseNavigator.push(context, const HelpView()),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            _AccessCard(
              profile: profile,
              onChange: () => BaseNavigator.push(context, const ProfilesView()),
              onHelp: () => BaseNavigator.push(context, const HelpView()),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.glyph,
    required this.color,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onPressed,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      radius: AppCorner.xl,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlyphIcon(glyph, size: 44, color: color),
            const SizedBox(height: 14),
            Text(
              title,
              style: AppTextStyle.title2.of(context, emphasized: true),
            ),
            const SizedBox(height: 6),
            Text(body, style: AppTextStyle.subheadline.of(context).toLighter),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: onPressed,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.profile,
    required this.onChange,
    required this.onHelp,
  });

  final Profile profile;
  final VoidCallback onChange;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final login = profile.overrides.managedLogin;
    return generateSection(
      title: l.profiles,
      items: [
        ListItem(
          leading: const GlyphIcon(AppGlyphs.account),
          title: Text(profile.realLabel),
          subtitle: Text(
            login.isEmpty ? l.remote : '${l.provisioningLogin}: $login',
          ),
        ),
        ListItem(
          leading: const GlyphIcon(AppGlyphs.key),
          title: Text(l.simpleChangeAccess),
          trailing: const GlyphIcon(AppGlyphs.chevronForward),
          onTap: onChange,
        ),
        ListItem(
          leading: const GlyphIcon(AppGlyphs.info),
          title: Text(l.simpleHelp),
          trailing: const GlyphIcon(AppGlyphs.chevronForward),
          onTap: onHelp,
        ),
      ],
    );
  }
}
