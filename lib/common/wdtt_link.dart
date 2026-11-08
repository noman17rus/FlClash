import 'dart:core';

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
      dtlsPort > 0 &&
      wgPort > 0 &&
      localPort > 0 &&
      password.trim().isNotEmpty &&
      hashes.trim().isNotEmpty;
}

/// Extracts a `wdtt://...` link from arbitrary text.
String? extractWdttLink(String value) {
  final start = value.toLowerCase().indexOf('wdtt://');
  if (start < 0) return null;
  final end = value.substring(start).split(RegExp(r'[\s\r\n\t]')).first;
  return end
      .trim()
      .replaceAll(RegExp(r'[.,;)\]\}"' "'" r']+$'), '')
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
  return WdttLinkParts(
    host: host,
    dtlsPort: dtlsPort,
    wgPort: wgPort,
    localPort: localPort,
    password: password,
    hashes: hashes,
    profileName: params['name'] ?? '',
    maxWorkers: maxWorkers,
  );
}

extension WdttLinkExtension on String {
  bool get isWdttLink => parseWdttLink(this) != null;
}