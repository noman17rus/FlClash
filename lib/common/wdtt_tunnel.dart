import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';

/// Manages the WDTT Go client process that exposes a local SOCKS5 proxy.
class WdttTunnelManager {
  Process? _process;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start(WdttLinkParts parts) async {
    await stop();
    if (!system.isAndroid) return;
    final nativeDir = await app?.getNativeLibraryDir();
    if (nativeDir == null || nativeDir.isEmpty) {
      throw StateError('Native library directory is unavailable');
    }
    final binary = File('$nativeDir/libclient.so');
    if (!await binary.exists()) {
      throw StateError('libclient.so is not bundled with this build');
    }
    final args = <String>[
      '-peer',
      '${parts.host}:${parts.dtlsPort}',
      '-startup-config-stdin=true',
      '-n',
      '4',
      '-listen',
      '127.0.0.1:${parts.localPort}',
      '-mode',
      'auto',
      '-socks-listen',
      '127.0.0.1:1080',
      '-socks-udp=true',
      '-socks-auth=false',
      '-device-id',
      'flclash',
      '-captcha-mode',
      'auto',
      '-vkcalls-preflight=false',
    ];
    final process = await Process.start(
      binary.path,
      args,
      environment: {'LD_LIBRARY_PATH': nativeDir},
      workingDirectory: Directory.systemTemp.path,
    );
    _process = process;
    _running = true;

    final payload = jsonEncode({
      'vk_hashes': parts.hashes,
      'connection_password': parts.password,
      'custom_vk_client_id': '',
      'custom_vk_client_secret': '',
      'socks_username': '',
      'socks_password': '',
    });
    final encoded = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
    process.stdin.writeln('START_CONFIG|$encoded');
    await process.stdin.flush();
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _running = false;
    if (process == null) return;
    process.kill();
    await process.exitCode.catchError((_) => -1);
  }
}

final wdttTunnelManager = WdttTunnelManager();