import 'package:fl_clash/common/wdtt_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leaves exclusive automatic selection to the Android service', () {
    final config = wdttFallbackConfig([
      {'name': 'Primary', 'type': 'vless'},
      {'name': 'Second', 'type': 'vless'},
      {'name': 'Unrelated', 'type': 'trojan'},
    ], 17);
    final [route, automatic, vless] = (config['proxy-groups'] as List)
        .cast<Map>();
    expect(route['type'], 'select');
    expect(route['proxies'], ['Auto [17]', 'VLESS [17]', 'WDTT [17]']);
    expect(automatic['type'], 'select');
    expect(automatic['proxies'], ['VLESS [17]', 'WDTT [17]']);
    expect(automatic.containsKey('url'), isFalse);
    expect(vless['type'], 'fallback');
    expect(vless['proxies'], ['Primary', 'Second']);
    expect(vless['lazy'], isTrue);
    expect(config['rules'], ['MATCH,VLESS / WDTT [17]']);
  });

  const link =
      'wdtt://connect?v=1&host=example.com&dtls=56000&wg=56001&local=9000&password=test%2Bpassword&hashes=test-hash';

  test('parses a WDTT link', () {
    final parts = parseWdttLink(link);
    expect(parts, isNotNull);
    expect(parts!.host, 'example.com');
    expect(parts.dtlsPort, 56000);
    expect(parts.wgPort, 56001);
    expect(parts.localPort, 9000);
    expect(parts.password, 'test+password');
    expect(parts.hashes, 'test-hash');
  });

  test('extracts a WDTT link from text', () {
    expect(extractWdttLink('prefix $link suffix'), link);
  });

  test('isWdttLink recognizes the link', () {
    expect(link.isWdttLink, isTrue);
    expect('https://example.com'.isWdttLink, isFalse);
  });

  test('rejects invalid WDTT links', () {
    expect(
      parseWdttLink(
        'wdtt://connect?v=2&host=x&dtls=1&wg=2&local=3&password=p&hashes=h',
      ),
      isNull,
    );
    expect(parseWdttLink('wdtt://connect?v=1&host=x'), isNull);
    expect(
      parseWdttLink(link.replaceFirst('dtls=56000', 'dtls=65536')),
      isNull,
    );
    expect(parseWdttLink(link.replaceFirst('local=9000', 'local=0')), isNull);
  });
}
