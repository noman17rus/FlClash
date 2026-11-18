import 'dart:async';

import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/profiles/bye_dpi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channel = Service().methodChannel;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      const TestApp(
        wrapInProviderScope: true,
        locale: Locale('ru'),
        child: ByeDpiView(selected: '-d1'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'refresh preserves a removed selection and testing ranks both services first',
    (tester) async {
      final tested = <String>[];
      final applied = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'byeDpiCatalog' => {
            'strategies': ['-o2'],
            'updated': 0,
          },
          'byeDpiNetwork' => 3,
          'byeDpiProbe' => () {
            final line = call.arguments['strategy'] as String;
            tested.add(line);
            return {
              'Google': line == '-o2' ? null : 12,
              'YouTube': line == '-o2' ? 25 : null,
              'YouTubeError': line == '-o2'
                  ? null
                  : 'TLS · SocketTimeoutException',
            };
          }(),
          'byeDpiValidate' => () {
            applied.add(call.arguments['strategy'] as String);
            throw PlatformException(code: 'BYEDPI', message: 'probe error');
          }(),
          _ => null,
        };
      });
      await open(tester);
      await tester.tap(find.text('Обновить список стратегий'));
      await tester.pumpAndSettle();
      expect(find.text('-d1'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Автоподбор стратегий'),
        findsOneWidget,
      );
      await tester.tap(find.text('Автоподбор стратегий'));
      await tester.pumpAndSettle();
      expect(tested, ['-d1', '-o2']);
      expect(applied, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Сайт YouTube доступен · 25 ms'),
        200,
      );
      expect(find.text('Сайт YouTube доступен · 25 ms'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('TLS · SocketTimeoutException'),
        200,
      );
      expect(find.text('TLS · SocketTimeoutException'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Применить сейчас'), -200);
      await tester.tap(find.text('Применить сейчас'));
      await tester.pumpAndSettle();
      expect(applied, ['-o2']);
      expect(find.text('probe error'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancelling a probe ignores its late result', (tester) async {
    final pending = Completer<Map<String, int>>();
    var probes = 0;
    var cancelled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'byeDpiCatalog':
          return {
            'strategies': ['-o2'],
            'updated': 0,
          };
        case 'byeDpiNetwork':
          return 3;
        case 'byeDpiProbe':
          probes++;
          return pending.future;
        case 'byeDpiCancel':
          cancelled = true;
      }
      return null;
    });
    await open(tester);
    await tester.tap(find.text('Автоподбор стратегий'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    pending.complete({'Google': 10, 'YouTube': 10});
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(probes, 1);
    expect(find.textContaining('10 ms'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
