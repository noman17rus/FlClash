import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _url =
    '$provisioningOrigin/api/v1/subscriptions/abcdefghijklmnopqrstuvwxyz0123456789_ABCD';
const _wdtt =
    'wdtt://connect?v=1&host=hub.everens.online&dtls=56000&wg=56001&local=9000&password=secret&hashes=hash';

Map<String, dynamic> _account() => {
  'account_id': 'account',
  'login': 'example@gmail.com',
  'subscription_url': _url,
  'wdtt_link': _wdtt,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppLocalizations.load(const Locale('en')));

  test('accepts names and emails and rejects invalid logins', () {
    expect(
      normalizeProvisioningLogin(' Example@Gmail.com '),
      'example@gmail.com',
    );
    expect(validProvisioningLogin(' Имя '), isTrue);
    for (final value in ['', ' ', 'x' * 255, 'a\nb', 'a\u200bb']) {
      expect(validProvisioningLogin(value), isFalse);
    }
  });

  test('only trusts HTTPS subscription URLs from the configured origin', () {
    expect(isProvisioningSubscription(_url), isTrue);
    for (final value in [
      _url.replaceFirst('https:', 'http:'),
      _url.replaceFirst('hub.everens.online', 'other.example'),
      '$_url?secret=1',
      '$_url#fragment',
      '$provisioningOrigin/api/v1/subscriptions/short',
    ]) {
      expect(isProvisioningSubscription(value), isFalse);
    }
    expect(ProvisionedAccount.fromJson(_account()).wdttLink, _wdtt);
    expect(
      () =>
          ProvisionedAccount.fromJson({..._account(), 'wdtt_link': 'invalid'}),
      throwsFormatException,
    );
  });

  test('provision and refresh use the public contract', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                data: _account(),
                statusCode: 200,
              ),
            );
          },
        ),
      );
    final client = ProvisioningClient(dio: dio);
    expect((await client.provision(' Example@gmail.com ')).id, 'account');
    expect((await client.refresh(_url)).login, 'example@gmail.com');
    expect(requests.first.method, 'POST');
    expect(requests.first.data, {'login': 'Example@gmail.com'});
    expect(requests.last.uri.toString(), '$_url/metadata');
    dio.close();
  });

  test('errors never expose upstream response or credentials', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              message: 'private-token-password',
            ),
          ),
        ),
      );
    await expectLater(
      ProvisioningClient(dio: dio).provision('name'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          isNot(contains('private-token')),
        ),
      ),
    );
    dio.close();
  });

  test('managed settings round-trip and legacy profiles remain unmanaged', () {
    final original = Profile.normal(label: 'managed', url: _url).copyWith(
      autoUpdateDuration: const Duration(hours: 1),
      overrides: const ProfileOverrides(
        managedAccountId: 'account',
        managedLogin: 'example@gmail.com',
        wdttFallbackLink: _wdtt,
        vlessEnabled: false,
        googleByeDpi: true,
      ),
    );
    final restored = Profile.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );
    expect(restored, original);
    expect(restored.isManaged, isTrue);
    expect(restored.overrides.wdttEnabled, isTrue);
    final legacy = original.toJson()
      ..['overrides'] = {'wdttFallbackLink': _wdtt};
    final imported = Profile.fromJson(legacy);
    expect(imported.isManaged, isFalse);
    expect(imported.overrides.wdttFallbackLink, _wdtt);
    expect(imported.overrides.googleByeDpi, isFalse);
    expect(imported.url, _url);
  });
}
