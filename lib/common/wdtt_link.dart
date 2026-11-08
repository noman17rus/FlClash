import 'constant.dart';

enum WdttRouteMode { automatic, vless, wdtt }

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

Map<String, dynamic> wdttFallbackConfig(
  List<Map<String, dynamic>> proxies,
  int profileId,
) {
  final route = wdttRouteGroupName(profileId);
  final wdtt = WdttRouteMode.wdtt.proxyName(profileId);
  final primary = [
    for (final proxy in proxies)
      if (proxy['type'] == 'vless') proxy['name'],
  ];
  Map<String, dynamic> fallback(WdttRouteMode mode, List<dynamic> members) => {
    'name': mode.proxyName(profileId),
    'type': 'fallback',
    'hidden': true,
    'proxies': members,
    'url': defaultTestUrl,
    'expected-status': '204',
    'interval': 15,
    'timeout': 5000,
    'lazy': false,
  };
  return {
    'proxies': [...proxies, wdttProxyConfig(wdtt)],
    'proxy-groups': [
      {
        'name': route,
        'type': 'select',
        'hidden': true,
        'proxies': [
          for (final mode in WdttRouteMode.values) mode.proxyName(profileId),
        ],
      },
      fallback(WdttRouteMode.automatic, [...primary, wdtt]),
      fallback(WdttRouteMode.vless, primary),
    ],
    'rules': ['MATCH,$route'],
  };
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
