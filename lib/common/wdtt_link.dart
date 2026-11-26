import 'constant.dart';

enum WdttRouteMode { automatic, vless, wdtt }

const wdttWhitelistName = 'FlClash WDTT whitelist';
const wdttWhitelistUrl =
    'https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/whitelist.txt';
const warpProxyName = 'WARP';

String warpRouteGroupName(int profileId) => 'WARP [$profileId]';

String wdttTransportName(int profileId) => 'WDTT transport [$profileId]';
String vlessTransportName(int profileId) => 'VLESS transport [$profileId]';
String wdttRulesName(int profileId) => 'WDTT rules [$profileId]';
String vlessRulesName(int profileId) => 'VLESS rules [$profileId]';

String wdttRouteGroupName(int profileId) => 'VLESS / WDTT [$profileId]';

extension WdttRouteModeName on WdttRouteMode {
  String proxyName(int profileId) => switch (this) {
    WdttRouteMode.automatic => 'Auto [$profileId]',
    WdttRouteMode.vless => 'VLESS [$profileId]',
    WdttRouteMode.wdtt => 'WDTT [$profileId]',
  };
}

Map<String, dynamic> wdttProxyConfig(String name) => {
  'name': name,
  'type': 'socks5',
  'server': localhost,
  'port': 1080,
  'udp': true,
};

Map<String, dynamic> wdttStandaloneConfig(
  int profileId, {
  bool googleByeDpi = false,
}) => {
  'proxies': [
    wdttProxyConfig('WDTT'),
    if (googleByeDpi)
      {
        'name': 'ByeDPI [$profileId]',
        'type': 'socks5',
        'server': localhost,
        'port': 11081,
        'udp': true,
      },
  ],
  'proxy-groups': [
    {
      'name': 'WDTT Group',
      'type': 'select',
      'proxies': ['WDTT'],
    },
    if (googleByeDpi)
      for (final service in ['YouTube', 'Google'])
        {
          'name': '$service [$profileId]',
          'type': 'fallback',
          'proxies': ['ByeDPI [$profileId]', 'WDTT'],
          'url': service == 'YouTube'
              ? 'https://www.youtube.com/'
              : defaultTestUrl,
          'expected-status': service == 'YouTube' ? '200' : '204',
          'interval': 30,
          'timeout': 5000,
          'lazy': false,
        },
  ],
  'rules': ['MATCH,WDTT'],
};

Map<String, dynamic> wdttFallbackConfig(
  List<Map<String, dynamic>> proxies,
  int profileId, {
  bool googleByeDpi = false,
}) {
  final route = wdttRouteGroupName(profileId);
  final wdtt = WdttRouteMode.wdtt.proxyName(profileId);
  final hasWarp = proxies.any(
    (proxy) => proxy['name'] == warpProxyName && proxy['type'] == 'vless',
  );
  final primary = [
    for (final proxy in proxies)
      if (proxy['type'] == 'vless' && proxy['name'] != warpProxyName)
        proxy['name'],
  ];
  Map<String, dynamic> fallback(List<dynamic> members) => {
    'name': vlessTransportName(profileId),
    'type': 'fallback',
    'hidden': true,
    'proxies': members,
    'url': defaultTestUrl,
    'expected-status': '204',
    // The Android monitor owns frequent checks; keep Core's lazy safety check sparse.
    'interval': 300,
    'timeout': 5000,
    'lazy': true,
  };
  return {
    'proxies': [
      ...proxies,
      wdttProxyConfig(wdttTransportName(profileId)),
      for (final entry in {
        WdttRouteMode.vless.proxyName(profileId): vlessRulesName(profileId),
        wdtt: wdttRulesName(profileId),
      }.entries)
        {'name': entry.key, 'type': 'rematch', 'target-sub-rule': entry.value},
      if (googleByeDpi)
        {
          'name': 'ByeDPI [$profileId]',
          'type': 'socks5',
          'server': localhost,
          'port': 11081,
          'udp': true,
        },
    ],
    'proxy-groups': [
      {
        'name': route,
        'type': 'select',
        'hidden': true,
        'proxies': [
          for (final mode in WdttRouteMode.values) mode.proxyName(profileId),
          if (hasWarp) warpRouteGroupName(profileId),
        ],
      },
      {
        'name': WdttRouteMode.automatic.proxyName(profileId),
        'type': 'select',
        'hidden': true,
        'proxies': [WdttRouteMode.vless.proxyName(profileId), wdtt],
      },
      if (hasWarp)
        {
          'name': warpRouteGroupName(profileId),
          'type': 'select',
          'hidden': true,
          'proxies': [warpProxyName],
        },
      fallback(primary),
      if (googleByeDpi)
        for (final service in ['YouTube', 'Google'])
          {
            'name': '$service [$profileId]',
            'type': 'fallback',
            'hidden': true,
            'proxies': ['ByeDPI [$profileId]', vlessTransportName(profileId)],
            'url': service == 'YouTube'
                ? 'https://www.youtube.com/'
                : 'https://www.gstatic.com/generate_204',
            'expected-status': service == 'YouTube' ? '200' : '204',
            'interval': 30,
            'timeout': 5000,
            'lazy': false,
          },
    ],
  };
}

void applyWdttRouting(
  Map<dynamic, dynamic> config,
  int profileId, {
  required String whitelistPath,
  bool standalone = false,
  bool googleByeDpi = false,
}) {
  final providers = config['rule-providers'] as Map? ?? const {};
  if (providers.containsKey(wdttWhitelistName)) {
    throw const FormatException('Reserved WDTT whitelist provider name');
  }
  config['rule-providers'] = {
    ...providers,
    wdttWhitelistName: {
      'type': 'http',
      'behavior': 'domain',
      'format': 'text',
      'url': wdttWhitelistUrl,
      'path': whitelistPath,
      'interval': 86400,
      'size-limit': 1048576,
    },
  };
  final directRules = [
    'RULE-SET,$wdttWhitelistName,DIRECT',
    'MATCH,${standalone ? 'WDTT' : wdttTransportName(profileId)}',
  ];
  if (standalone) {
    config['rules'] = [
      if (googleByeDpi) ...[
        'GEOSITE,youtube,YouTube [$profileId]',
        'GEOSITE,google,Google [$profileId]',
      ],
      ...directRules,
    ];
  } else {
    final subRules = config['sub-rules'] as Map? ?? const {};
    if (subRules.containsKey(vlessRulesName(profileId)) ||
        subRules.containsKey(wdttRulesName(profileId))) {
      throw const FormatException('Reserved WDTT sub-rule name');
    }
    config['sub-rules'] = {
      ...subRules,
      vlessRulesName(profileId): [
        'AND,((IN-TYPE,INNER),(DOMAIN,raw.githubusercontent.com)),${vlessTransportName(profileId)}',
        if (googleByeDpi) ...[
          'GEOSITE,youtube,YouTube [$profileId]',
          'GEOSITE,google,Google [$profileId]',
        ],
        ...config['rules'] as List,
        'MATCH,${vlessTransportName(profileId)}',
      ],
      wdttRulesName(profileId): directRules,
    };
    config['rules'] = ['MATCH,${wdttRouteGroupName(profileId)}'];
  }
  final dns = Map<String, dynamic>.from(config['dns'] as Map? ?? {});
  dns['direct-nameserver'] = ['system'];
  dns['direct-nameserver-follow-policy'] = false;
  dns['nameserver-policy'] = {
    'rule-set:$wdttWhitelistName': ['system'],
    ...?dns['nameserver-policy'] as Map?,
  };
  config['dns'] = dns;
  config['mode'] = 'rule';
}

/// Parsed parameters of a `wdtt://connect?...` tunnel link.
class WdttLinkParts {
  final String host;
  final int dtlsPort;
  final int wgPort;
  final int localPort;
  final String password;
  final String hashes;
  final String profileName;
  final int maxWorkers;

  const WdttLinkParts({
    required this.host,
    required this.dtlsPort,
    required this.wgPort,
    required this.localPort,
    required this.password,
    required this.hashes,
    this.profileName = '',
    this.maxWorkers = 0,
  });

  bool get isValid =>
      host.trim().isNotEmpty &&
      _validPort(dtlsPort) &&
      _validPort(wgPort) &&
      _validPort(localPort) &&
      password.trim().isNotEmpty &&
      hashes.trim().isNotEmpty;
}

bool _validPort(int port) => port > 0 && port <= 65535;

/// Extracts a `wdtt://...` link from arbitrary text.
String? extractWdttLink(String value) {
  final start = value.toLowerCase().indexOf('wdtt://');
  if (start < 0) return null;
  final end = value.substring(start).split(RegExp(r'[\s\r\n\t]')).first;
  return end
      .trim()
      .replaceAll(
        RegExp(
          r'[.,;)\]\}"'
          "'"
          r']+$',
        ),
        '',
      )
      .trim();
}

WdttLinkParts? parseWdttLink(String value) {
  final clean = extractWdttLink(value);
  if (clean == null) return null;
  final uri = Uri.tryParse(clean);
  if (uri == null || uri.scheme.toLowerCase() != 'wdtt') return null;
  if (uri.host.toLowerCase() != 'connect') {
    // Some encoders put "connect" in the path instead of the host.
    if (uri.pathSegments.isEmpty ||
        uri.pathSegments.first.toLowerCase() != 'connect') {
      return null;
    }
  }
  final params = uri.queryParameters;
  if (params['v'] != '1') return null;
  final host = params['host']?.trim() ?? '';
  final dtlsPort = int.tryParse(params['dtls'] ?? '');
  final wgPort = int.tryParse(params['wg'] ?? '');
  final localPort = int.tryParse(params['local'] ?? '');
  final password = params['password'] ?? '';
  final hashes = params['hashes'] ?? '';
  if (host.isEmpty ||
      dtlsPort == null ||
      wgPort == null ||
      localPort == null ||
      password.trim().isEmpty ||
      hashes.trim().isEmpty) {
    return null;
  }
  final maxWorkersRaw = params['max_workers'];
  int maxWorkers = 0;
  if (maxWorkersRaw != null && maxWorkersRaw.trim().isNotEmpty) {
    final parsed = int.tryParse(maxWorkersRaw.trim());
    if (parsed == null) return null;
    maxWorkers = parsed;
  }
  final parts = WdttLinkParts(
    host: host,
    dtlsPort: dtlsPort,
    wgPort: wgPort,
    localPort: localPort,
    password: password,
    hashes: hashes,
    profileName: params['name'] ?? '',
    maxWorkers: maxWorkers,
  );
  return parts.isValid ? parts : null;
}

extension WdttLinkExtension on String {
  bool get isWdttLink => parseWdttLink(this) != null;

  bool get isVlessLink => trimLeft().toLowerCase().startsWith('vless://');
}
