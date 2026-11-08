import 'package:fl_clash/common/wdtt_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const link =
      'wdtt://connect?v=1&host=193.163.86.172&dtls=56000&wg=56001&local=9000&password=bD8ZmxEcqxbDQ5E5&hashes=pissbIbFy27ZFBrRKoSWcsISyW7k3lRk4fFoTo3t6SM';

  test('parses a WDTT link', () {
    final parts = parseWdttLink(link);
    expect(parts, isNotNull);
    expect(parts!.host, '193.163.86.172');
    expect(parts.dtlsPort, 56000);
    expect(parts.wgPort, 56001);
    expect(parts.localPort, 9000);
    expect(parts.password, 'bD8ZmxEcqxbDQ5E5');
    expect(parts.hashes, 'pissbIbFy27ZFBrRKoSWcsISyW7k3lRk4fFoTo3t6SM');
  });

  test('extracts a WDTT link from text', () {
    expect(extractWdttLink('prefix $link suffix'), link);
  });

  test('isWdttLink recognizes the link', () {
    expect(link.isWdttLink, isTrue);
    expect('https://example.com'.isWdttLink, isFalse);
  });

  test('rejects invalid WDTT links', () {
    expect(parseWdttLink('wdtt://connect?v=2&host=x&dtls=1&wg=2&local=3&password=p&hashes=h'), isNull);
    expect(parseWdttLink('wdtt://connect?v=1&host=x'), isNull);
  });
}