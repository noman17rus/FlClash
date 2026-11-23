import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

class _FailingAction extends ProfilesAction {
  final attempts = <({String login, String label})>[];

  @override
  Future<Profile> addManagedProfile(String login, {String label = ''}) async {
    attempts.add((login: login, label: label));
    throw const FormatException('private server error');
  }
}

void main() {
  testWidgets('primary add opens registration and preserves other imports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1000, 900);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          child: Scaffold(
            title: 'Profiles',
            body: AddProfileMenu(
              managedPrimary: true,
              builder: (open) =>
                  TextButton(onPressed: open, child: const Text('add')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    expect(find.byType(ManagedProfileForm), findsOneWidget);
    await tester.tap(find.text('Other import methods'));
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
  });

  testWidgets('requires a login and allows retry without clearing input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final action = _FailingAction();
    final container = ProviderContainer(
      overrides: [profilesActionProvider.overrideWith(() => action)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1000, 900);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(locale: Locale('en'), child: ManagedProfileForm()),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ManagedProfileForm));
    await tester.tap(find.byTooltip('Submit'));
    await tester.pumpAndSettle();
    expect(action.attempts, isEmpty);
    expect(
      find.text(context.appLocalizations.provisioningLoginInvalid),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      'Example@gmail.com',
    );
    await tester.tap(find.byTooltip('Submit'));
    await tester.pumpAndSettle();
    expect(action.attempts.single, (login: 'Example@gmail.com', label: ''));
    expect(
      find.text(context.appLocalizations.provisioningFailed),
      findsOneWidget,
    );
    expect(find.text('private server error'), findsNothing);
    await tester.tap(find.byTooltip('Submit'));
    await tester.pumpAndSettle();
    expect(action.attempts, hasLength(2));
    expect(find.widgetWithText(FormRow, 'Name or email'), findsOneWidget);
    expect(find.text('Other import methods'), findsOneWidget);
  });
}
