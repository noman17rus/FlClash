import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

void main() {
  test('WDTT-only with ByeDPI has no VLESS dependency', () async {
    final raw = wdttStandaloneConfig(7, googleByeDpi: true);
    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: 'profiles',
        profileId: 7,
        rawConfig: raw,
        realPatchConfig: const PatchClashConfig(mode: Mode.global),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash-Test',
      ),
      wdttStandalone: true,
      googleByeDpi: true,
    );
    final built = loadYaml(result.yaml) as YamlMap;
    expect(
      built['rules'],
      containsAllInOrder([
        'GEOSITE,youtube,YouTube [7]',
        'GEOSITE,google,Google [7]',
        'MATCH,WDTT',
      ]),
    );
    expect(built['proxies'].any((dynamic p) => p['type'] == 'vless'), isFalse);
    expect(
      built['proxy-groups'].firstWhere(
        (dynamic g) => g['name'] == 'YouTube [7]',
      )['proxies'],
      ['ByeDPI [7]', 'WDTT'],
    );
    expect(built['mode'], 'rule');
  });

  test('WDTT wraps the final VLESS rules after profile overrides', () async {
    final config = wdttFallbackConfig([
      {'name': 'Primary', 'type': 'vless'},
    ], 7);
    config['rules'] = ['DOMAIN,blocked.test,Primary', 'MATCH,DIRECT'];
    config['rule-providers'] = {
      'blocked': {'type': 'http', 'url': 'https://example.com/blocked.txt'},
    };
    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: path.join('profiles'),
        profileId: 7,
        rawConfig: config,
        realPatchConfig: const PatchClashConfig(mode: Mode.global),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [
          Rule(
            ruleAction: RuleAction.DOMAIN,
            content: 'extra.test',
            ruleTarget: 'DIRECT',
          ),
        ],
        defaultUA: 'FlClash-Test',
      ),
      wdttFallback: true,
    );
    final built = loadYaml(result.yaml) as YamlMap;
    expect(built['mode'], 'rule');
    expect(built['rules'], ['MATCH,VLESS / WDTT [7]']);
    expect(
      built['sub-rules']['VLESS rules [7]'],
      containsAllInOrder([
        'DOMAIN,extra.test,DIRECT',
        'DOMAIN,blocked.test,Primary',
        'MATCH,DIRECT',
      ]),
    );
    expect(built['sub-rules']['WDTT rules [7]'], [
      'RULE-SET,$wdttWhitelistName,DIRECT',
      'MATCH,WDTT transport [7]',
    ]);
    expect(built['rule-providers'], contains('blocked'));
    expect(
      built['rule-providers'][wdttWhitelistName]['path'],
      startsWith(path.join('profiles', 'providers', '7', 'rules')),
    );
    expect(built['dns']['direct-nameserver'], ['system']);
  });

  test(
    'standalone WDTT replaces direct added rules after all merges',
    () async {
      final result = await makeRealProfileTask(
        const MakeRealProfileState(
          profilesPath: 'profiles',
          profileId: 7,
          rawConfig: {
            'rules': ['MATCH,WDTT Group'],
          },
          realPatchConfig: PatchClashConfig(mode: Mode.direct),
          appendSystemDns: false,
          proxyGroups: [],
          rules: [],
          addedRules: [
            Rule(ruleAction: RuleAction.MATCH, ruleTarget: 'DIRECT'),
          ],
          defaultUA: 'FlClash-Test',
        ),
        wdttStandalone: true,
      );
      final built = loadYaml(result.yaml) as YamlMap;
      expect(built['mode'], 'rule');
      expect(built['rules'], [
        'RULE-SET,$wdttWhitelistName,DIRECT',
        'MATCH,WDTT',
      ]);
    },
  );
}
