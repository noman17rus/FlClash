import 'package:fl_clash/common/wdtt_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'routes Google and YouTube separately with the current tunnel as backup',
    () {
      final config = wdttFallbackConfig(
        [
          {'name': 'Primary', 'type': 'vless'},
        ],
        17,
        googleByeDpi: true,
      );
      expect(config['rules'], [
        'GEOSITE,youtube,YouTube [17]',
        'GEOSITE,google,Google [17]',
        'MATCH,VLESS / WDTT [17]',
      ]);
      final groups = (config['proxy-groups'] as List).cast<Map>();
      expect(groups.first['proxies'], ['Auto [17]', 'VLESS [17]', 'WDTT [17]']);
      final services = groups.skip(3).toList();
      expect(services.map((group) => group['url']).toSet(), hasLength(2));
      expect(services.first['url'], 'https://www.youtube.com/');
      expect(services.first['expected-status'], '200');
      expect(services.last['expected-status'], '204');
      for (final group in services) {
        expect(group['proxies'], ['ByeDPI [17]', 'VLESS / WDTT [17]']);
        expect(group['type'], 'fallback');
      }
    },
  );

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
    expect(vless['interval'], 300);
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
