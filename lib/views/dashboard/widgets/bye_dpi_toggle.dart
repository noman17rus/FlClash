import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardByeDpiToggle extends ConsumerWidget {
  const DashboardByeDpiToggle({
    super.key,
    required this.profileId,
    this.unavailable = false,
  });

  final int profileId;
  final bool unavailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(profileId));
    if (profile == null) return const SizedBox.shrink();
    final enabled =
        !unavailable &&
        profile.overrides.wdttFallbackLink.isWdttLink &&
        (!profile.isManaged || profile.overrides.wdttEnabled);
    final label = context.appLocalizations.byeDpiGoogle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: Text(label, style: AppTextStyle.footnote.of(context)),
            ),
            Switch(
              value: profile.overrides.googleByeDpi,
              semanticLabel: label,
              onChanged: enabled
                  ? (value) {
                      ref
                          .read(profilesProvider.notifier)
                          .updateProfile(
                            profileId,
                            (latest) => latest.copyWith(
                              overrides: latest.overrides.copyWith(
                                googleByeDpi: value,
                              ),
                            ),
                          );
                      ref
                          .read(setupActionProvider.notifier)
                          .applyProfileDebounce();
                    }
                  : null,
            ),
          ],
        ),
        Text(
          unavailable
              ? context.appLocalizations.byeDpiUnavailableMobile
              : context.appLocalizations.byeDpiDescription,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
