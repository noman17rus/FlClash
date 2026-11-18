import 'dart:async';

import 'package:fl_clash/views/connection_mode.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows modes and saves only after confirmation from Android', (
    tester,
  ) async {
    final response = Completer<String?>();
    final saved = <String>[];
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        locale: const Locale('ru'),
        child: ConnectionModeView(
          loadMode: () async => 'balanced',
          saveMode: (mode) {
            saved.add(mode);
            return response.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Экономичный'), findsOneWidget);
    expect(find.text('Сбалансированный'), findsOneWidget);
    expect(find.text('Быстрое восстановление'), findsOneWidget);
    expect(find.textContaining('180 с'), findsOneWidget);
    await tester.tap(find.text('Экономичный'));
    await tester.pump();
    await tester.tap(find.text('Экономичный'));
    expect(saved, ['economical']);
    response.complete('economical');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Экономичный'));
    expect(saved, ['economical']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed save preserves selection and permits retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        locale: const Locale('ru'),
        child: ConnectionModeView(
          loadMode: () async => 'balanced',
          saveMode: (mode) async {
            if (++calls == 1) throw StateError('unavailable');
            return mode;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Экономичный'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось'), findsOneWidget);
    await tester.tap(find.text('Экономичный'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('Не удалось'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
