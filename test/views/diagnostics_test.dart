import 'dart:async';

import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/diagnostics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('one tap checks all stages and explains a TURN failure', (
    tester,
  ) async {
    final response = Completer<Map<Object?, Object?>?>();
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentProfileProvider.overrideWith((ref) => null)],
        child: TestApp(
          locale: const Locale('ru'),
          child: DiagnosticsView(
            runDiagnostics: (_, _) {
              calls++;
              return response.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запустить диагностику'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Проверка…'), findsOneWidget);
    response.complete({
      'vless': 'passed',
      'turn': 'failed',
      'dtls': 'blocked',
      'wireguard': 'blocked',
      'dns': 'blocked',
      'internet': 'blocked',
    });
    await tester.pumpAndSettle();
    expect(find.text('VLESS — Успешно'), findsOneWidget);
    expect(find.text('Получение TURN-доступа — Сбой'), findsOneWidget);
    expect(find.textContaining('Обновите приглашение WDTT'), findsOneWidget);
    expect(find.text('DTLS — Заблокировано предыдущим этапом'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
