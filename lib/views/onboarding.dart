import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UxGate extends ConsumerStatefulWidget {
  const UxGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UxGate> createState() => _UxGateState();
}

class _UxGateState extends ConsumerState<UxGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _migrate());
    ref.listenManual(profilesProvider, (previous, next) {
      if (previous?.isNotEmpty != next.isNotEmpty) {
        _migrate();
      }
    });
  }

  void _migrate() {
    if (!mounted) return;
    final profiles = ref.read(profilesProvider);
    final settings = ref.read(appSettingProvider);
    if (profiles.isNotEmpty &&
        (!settings.onboardingCompleted || settings.simpleMode == null)) {
      ref
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              onboardingCompleted: true,
              simpleMode: state.simpleMode ?? false,
            ),
          );
    } else if (!system.isAndroid && settings.simpleMode == null) {
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(simpleMode: false));
    }
  }

  void _finish() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            onboardingCompleted: true,
            simpleMode: state.simpleMode ?? true,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingProvider);
    final profiles = ref.watch(profilesProvider);
    final showOnboarding =
        system.isAndroid && profiles.isEmpty && !settings.onboardingCompleted;
    if (!showOnboarding) {
      return widget.child;
    }
    return OnboardingView(onFinished: _finish);
  }
}

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _login = TextEditingController();
  var _page = 0;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l = context.appLocalizations;
    if (!validProvisioningLogin(_login.text)) {
      setState(() => _error = l.provisioningLoginInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(profilesActionProvider.notifier)
          .addManagedProfile(_login.text);
      if (mounted) {
        widget.onFinished();
      }
    } on ProvisioningException catch (error) {
      if (mounted) {
        setState(() => _error = provisioningErrorMessage(error.kind));
      }
    } on MessageException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l.provisioningErrorUnknown);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_page == 0)
                    const SizedBox(width: 48)
                  else
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _page = 0),
                      icon: const GlyphIcon(AppGlyphs.chevronBack),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : widget.onFinished,
                    child: Text(l.onboardingSkip),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: _page == 0
                      ? _Welcome(
                          onContinue: () => setState(() => _page = 1),
                          onHaveLogin: () => setState(() => _page = 1),
                        )
                      : _Login(
                          controller: _login,
                          saving: _saving,
                          error: _error,
                          onSubmit: _submit,
                        ),
                ),
              ),
              if (_page == 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const ActivityIndicator(size: 20)
                        : Text(l.onboardingGetAccess),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onContinue, required this.onHaveLogin});

  final VoidCallback onContinue;
  final VoidCallback onHaveLogin;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const GlyphIcon(AppGlyphs.lock, size: 56),
        const SizedBox(height: 20),
        Text(
          l.onboardingTitle,
          style: AppTextStyle.title1.of(context, emphasized: true),
        ),
        const SizedBox(height: 10),
        Text(
          l.onboardingIntro,
          style: AppTextStyle.subheadline.of(context).copyWith(height: 1.45),
        ),
        const SizedBox(height: 24),
        Card(
          radius: AppCorner.xl,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.onboardingWhatTitle,
                  style: AppTextStyle.headline.of(context),
                ),
                const SizedBox(height: 6),
                Text(
                  l.onboardingWhatBody,
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: onContinue,
            child: Text(l.continueText),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: onHaveLogin,
            child: Text(l.onboardingHaveLogin),
          ),
        ),
      ],
    );
  }
}

class _Login extends StatelessWidget {
  const _Login({
    required this.controller,
    required this.saving,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool saving;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          l.onboardingHaveLogin,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        const SizedBox(height: 8),
        Text(
          l.provisioningLoginHelp,
          style: AppTextStyle.subheadline.of(context).copyWith(height: 1.45),
        ),
        const SizedBox(height: 16),
        FilledInputTheme(
          borderRadius: AppRadius.lg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: TextField(
            controller: controller,
            autofocus: true,
            enabled: !saving,
            textInputAction: TextInputAction.done,
            inputFormatters: TextInputLimits.limit(254),
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(hintText: l.onboardingLoginHint),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.provisioningLoginExample,
          style: AppTextStyle.footnote.of(context).toLighter,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(message: error),
        ],
      ],
    );
  }
}
