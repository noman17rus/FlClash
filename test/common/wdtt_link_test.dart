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
      config['rules'] = ['DOMAIN,blocked.test,Primary', 'MATCH,DIRECT'];
      applyWdttRouting(
        config,
        17,
        whitelistPath: '/cache/white',
        googleByeDpi: true,
      );
      expect(config['rules'], ['MATCH,VLESS / WDTT [17]']);
      expect(config['sub-rules']['VLESS rules [17]'], [
        'AND,((IN-TYPE,INNER),(DOMAIN,raw.githubusercontent.com)),VLESS transport [17]',
        'GEOSITE,youtube,YouTube [17]',
        'GEOSITE,google,Google [17]',
        'DOMAIN,blocked.test,Primary',
        'MATCH,DIRECT',
        'MATCH,VLESS transport [17]',
      ]);
      expect(config['sub-rules']['WDTT rules [17]'], [
        'RULE-SET,$wdttWhitelistName,DIRECT',
        'MATCH,WDTT transport [17]',
      ]);
      final groups = (config['proxy-groups'] as List).cast<Map>();
      expect(groups.first['proxies'], ['Auto [17]', 'VLESS [17]', 'WDTT [17]']);
      final services = groups.skip(3).toList();
      expect(services.map((group) => group['url']).toSet(), hasLength(2));
      expect(services.first['url'], 'https://www.youtube.com/');
      expect(services.first['expected-status'], '200');
      expect(services.last['expected-status'], '204');
      for (final group in services) {
        expect(group['proxies'], ['ByeDPI [17]', 'VLESS transport [17]']);
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
    expect(vless['name'], 'VLESS transport [17]');
    expect(config.containsKey('rules'), isFalse);
    final entries = (config['proxies'] as List).cast<Map>();
    expect(
      entries.firstWhere((entry) => entry['name'] == 'WDTT [17]')['type'],
      'rematch',
    );
    expect(
      entries.firstWhere(
        (entry) => entry['name'] == 'WDTT transport [17]',
      )['type'],
      'socks5',
    );
  });

  test('standalone WDTT ignores broad direct overrides and updates daily', () {
    final config = <String, dynamic>{
      'mode': 'global',
      'rules': ['MATCH,DIRECT'],
      'dns': {'enable': true, 'enhanced-mode': 'fake-ip'},
    };
    applyWdttRouting(
      config,
      17,
      whitelistPath: '/cache/white',
      standalone: true,
    );
    expect(config['rules'], [
      'RULE-SET,$wdttWhitelistName,DIRECT',
      'MATCH,WDTT',
    ]);
    expect(config['mode'], 'rule');
    expect(
      config['rule-providers'][wdttWhitelistName]['url'],
      wdttWhitelistUrl,
    );
    expect(config['rule-providers'][wdttWhitelistName]['interval'], 86400);
    expect(config['dns']['direct-nameserver'], ['system']);
    expect(config['dns']['enhanced-mode'], 'fake-ip');
    expect(config['dns']['nameserver-policy']['rule-set:$wdttWhitelistName'], [
      'system',
    ]);
  });

  test('reserved provider and sub-rule names are rejected', () {
    expect(
      () => applyWdttRouting(
        {
          'rule-providers': {wdttWhitelistName: {}},
        },
        17,
        whitelistPath: '/cache/white',
      ),
      throwsFormatException,
    );
    expect(
      () => applyWdttRouting(
        {
          'sub-rules': {'WDTT rules [17]': []},
        },
        17,
        whitelistPath: '/cache/white',
      ),
      throwsFormatException,
    );
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
