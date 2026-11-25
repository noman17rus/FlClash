import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/widgets/bye_dpi_toggle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

class _TestSetupAction extends SetupAction {
  int applies = 0;

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    applies++;
  }
}

const _profile = Profile(
  id: 17,
  autoUpdateDuration: Duration(hours: 1),
  selectedMap: {'VLESS / WDTT [17]': 'WDTT [17]'},
  overrides: ProfileOverrides(
    wdttFallbackLink:
        'wdtt://connect?v=1&host=test.example&dtls=443&wg=51820&local=1080&password=secret&hashes=abc',
    byeDpiStrategy: '-d1',
  ),
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([_profile])),
        setupActionProvider.overrideWith(_TestSetupAction.new),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pump(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
    double textScale = 1,
    bool unavailable = false,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('ru'),
          themeMode: themeMode,
          child: HostScaffold(
            body: SizedBox(
              width: 300,
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: textScale,
                maxScaleFactor: textScale,
                child: DashboardByeDpiToggle(
                  profileId: 17,
                  unavailable: unavailable,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Profile saved() => container.read(profilesProvider).single;

  testWidgets(
    'blocks selection on mobile failure and restores it without losing the saved choice',
    (tester) async {
      container
          .read(profilesProvider.notifier)
          .updateProfile(
            17,
            (profile) => profile.copyWith(
              overrides: profile.overrides.copyWith(googleByeDpi: true),
            ),
          );
      await pump(tester, unavailable: true);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        find.text(
          'Мобильная сеть: VLESS недоступен. Используйте WDTT. ByeDPI станет доступен после восстановления VLESS или перехода на Wi-Fi.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(saved().overrides.googleByeDpi, isTrue);
      await pump(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    },
  );

  testWidgets(
    'the explanation fits a narrow phone with large text in both themes',
    (tester) async {
      for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
        await pump(tester, themeMode: themeMode, textScale: 1.4);
        expect(find.textContaining('раз в сутки'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('toggles ByeDPI and applies without changing route or strategy', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Google и YouTube через ByeDPI'), findsOneWidget);
    expect(
      find.textContaining('При мобильных белых списках используйте WDTT'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(saved().overrides.googleByeDpi, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(saved().selectedMap, _profile.selectedMap);
    expect(saved().overrides.byeDpiStrategy, '-d1');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(saved().overrides.googleByeDpi, isFalse);
    expect(
      (container.read(setupActionProvider.notifier) as _TestSetupAction)
          .applies,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('follows profile changes from settings', (tester) async {
    await pump(tester);
    container
        .read(profilesProvider.notifier)
        .updateProfile(
          17,
          (profile) => profile.copyWith(
            overrides: profile.overrides.copyWith(googleByeDpi: true),
          ),
        );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('disables ByeDPI when managed WDTT is disabled', (tester) async {
    container
        .read(profilesProvider.notifier)
        .updateProfile(
          17,
          (profile) => profile.copyWith(
            overrides: profile.overrides.copyWith(
              managedAccountId: 'account',
              wdttEnabled: false,
            ),
          ),
        );
    await pump(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(saved().overrides.googleByeDpi, isFalse);
  });

  testWidgets('removes the toggle when the profile is deleted', (tester) async {
    await pump(tester);
    await container.read(profilesProvider.notifier).del(17);
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
