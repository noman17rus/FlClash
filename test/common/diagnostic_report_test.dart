import 'dart:convert';

import 'package:fl_clash/common/diagnostic_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'export discards secret fields and rejects secret-bearing status values',
    () {
      final report = exportDiagnosticReport({
        'vless': 'passed',
        'turn': 'password=secret-token',
        'dtls': {'privateKey': 'secret-key'},
        'wireguard': 'failed',
        'dns': 'blocked',
        'internet': 'blocked',
        'link': 'wdtt://connect?password=secret-password',
        'uuid': 'secret-uuid',
        'logs': ['Authorization: Bearer secret-bearer'],
        'config': {'PrivateKey': 'secret-config'},
      });
      expect(report, isNot(contains('secret')));
      final decoded = jsonDecode(report) as Map;
      expect(decoded['results'], {
        'vless': 'passed',
        'turn': 'unavailable',
        'dtls': 'unavailable',
        'wireguard': 'failed',
        'dns': 'blocked',
        'internet': 'blocked',
      });
    },
  );

  test('missing stages cannot become successful', () {
    expect(safeDiagnosticResults(null).values, everyElement('unavailable'));
  });
}
