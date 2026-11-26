import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'common.dart';

const provisioningOrigin = String.fromEnvironment(
  'PROVISIONING_URL',
  defaultValue: 'https://hub.everens.online',
);

String normalizeProvisioningLogin(String login) => login.trim().toLowerCase();

enum ProvisioningError {
  network,
  timeout,
  rateLimited,
  unavailable,
  invalid,
  notFound,
  unknown,
}

final class ProvisioningException implements Exception {
  final ProvisioningError kind;

  const ProvisioningException(this.kind);

  @override
  String toString() => 'ProvisioningException($kind)';
}

String provisioningErrorMessage(ProvisioningError kind) {
  final l = currentAppLocalizations;
  return switch (kind) {
    ProvisioningError.network => l.provisioningErrorNetwork,
    ProvisioningError.timeout => l.provisioningErrorTimeout,
    ProvisioningError.rateLimited => l.provisioningErrorRateLimited,
    ProvisioningError.unavailable => l.provisioningErrorServer,
    ProvisioningError.invalid => l.provisioningErrorInvalid,
    ProvisioningError.notFound => l.provisioningErrorNotFound,
    ProvisioningError.unknown => l.provisioningErrorUnknown,
  };
}

bool validProvisioningLogin(String login) {
  final value = login.trim();
  return value.isNotEmpty &&
      value.runes.length <= 254 &&
      !RegExp(r'\p{C}', unicode: true).hasMatch(value);
}

class ProvisionedAccount {
  final String id;
  final String login;
  final String subscriptionUrl;
  final String wdttLink;

  const ProvisionedAccount({
    required this.id,
    required this.login,
    required this.subscriptionUrl,
    required this.wdttLink,
  });

  factory ProvisionedAccount.fromJson(Map<String, dynamic> json) {
    final id = json['account_id'];
    final login = json['login'];
    final url = json['subscription_url'];
    final wdtt = json['wdtt_link'];
    if (id is! String ||
        id.isEmpty ||
        login is! String ||
        !validProvisioningLogin(login) ||
        url is! String ||
        !isProvisioningSubscription(url) ||
        wdtt is! String ||
        !wdtt.isWdttLink) {
      throw const FormatException('Invalid provisioning response');
    }
    return ProvisionedAccount(
      id: id,
      login: login,
      subscriptionUrl: url,
      wdttLink: wdtt,
    );
  }
}

bool isProvisioningSubscription(String value) {
  final uri = Uri.tryParse(value);
  final origin = Uri.parse(provisioningOrigin);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.origin == origin.origin &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      RegExp(r'^/api/v1/subscriptions/[A-Za-z0-9_-]{32,}$').hasMatch(uri.path);
}

class ProvisioningClient {
  final Dio _dio;

  ProvisioningClient({Dio? dio}) : _dio = dio ?? _createDio();

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 15),
        followRedirects: false,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..findProxy = ((_) => 'DIRECT')
        ..badCertificateCallback = ((_, _, _) => false),
    );
    return dio;
  }

  Future<ProvisionedAccount> provision(String login) {
    if (Uri.parse(provisioningOrigin).scheme != 'https') {
      throw const ProvisioningException(ProvisioningError.invalid);
    }
    return _read(
      () => _dio.post<Map<String, dynamic>>(
        '$provisioningOrigin/api/v1/provision',
        data: {'login': login.trim()},
      ),
    );
  }

  Future<ProvisionedAccount> refresh(String url) {
    if (!isProvisioningSubscription(url)) {
      throw const ProvisioningException(ProvisioningError.invalid);
    }
    return _read(() => _dio.get<Map<String, dynamic>>('$url/metadata'));
  }

  Future<ProvisionedAccount> _read(
    Future<Response<Map<String, dynamic>>> Function() fetch,
  ) async {
    try {
      final response = await fetch();
      return ProvisionedAccount.fromJson(response.data!);
    } on ProvisioningException {
      rethrow;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      throw ProvisioningException(
        statusCode != null
            ? switch (statusCode) {
                400 => ProvisioningError.invalid,
                404 => ProvisioningError.notFound,
                429 => ProvisioningError.rateLimited,
                >= 500 => ProvisioningError.unavailable,
                _ => ProvisioningError.unknown,
              }
            : switch (error.type) {
                DioExceptionType.connectionTimeout ||
                DioExceptionType.sendTimeout ||
                DioExceptionType.receiveTimeout => ProvisioningError.timeout,
                DioExceptionType.connectionError => ProvisioningError.network,
                _ => ProvisioningError.unknown,
              },
      );
    } on FormatException {
      throw const ProvisioningException(ProvisioningError.invalid);
    } catch (_) {
      throw const ProvisioningException(ProvisioningError.unknown);
    }
  }
}

final provisioningClient = ProvisioningClient();
