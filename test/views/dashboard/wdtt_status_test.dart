import 'package:fl_clash/views/dashboard/widgets/wdtt_status.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';
import '../../helpers/host_scaffold.dart';

void main() {
  Future<void> pump(WidgetTester tester, String phase) => tester.pumpWidget(
    TestApp(
      locale: const Locale('ru'),
      child: HostScaffold(
        body: WdttStatusPanel(
          status: {
            'phase': phase,
            'route': 'WDTT',
            'switchedAt': 1000,
            'events': [
              {'phase': 'backup', 'time': 1000},
              {'phase': 'primary', 'time': 0},
            ],
          },
        ),
      ),
    ),
  );

  testWidgets('backup explains the cause, time and recovery; history opens', (
    tester,
  ) async {
    await pump(tester, 'backup');
    await tester.pumpAndSettle();
    expect(find.text('WDTT — VLESS недоступен'), findsOneWidget);
    expect(find.textContaining('Время перехода:'), findsOneWidget);
    expect(
      find.text('Восстановление: ожидаем доступности VLESS'),
      findsOneWidget,
    );
    await tester.tap(find.text('Последние события подключения'));
    await tester.pumpAndSettle();
    expect(find.textContaining('VLESS — доступен'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.textContaining('VLESS — доступен'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual selection and recovery confirmation have distinct states',
    (tester) async {
      await pump(tester, 'manualWdtt');
      await tester.pumpAndSettle();
      expect(find.text('WDTT — выбран вручную'), findsOneWidget);
      expect(find.text('Автовозврат отключён в ручном режиме'), findsOneWidget);
      await pump(tester, 'recovering');
      await tester.pumpAndSettle();
      expect(find.text('WDTT — VLESS недоступен'), findsOneWidget);
      expect(
        find.text('Восстановление: проверяем стабильность VLESS'),
        findsOneWidget,
      );
    },
  );
}
