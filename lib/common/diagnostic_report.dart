import 'dart:convert';

const diagnosticStages = [
  'vless',
  'turn',
  'dtls',
  'wireguard',
  'dns',
  'internet',
];
const diagnosticStatuses = {
  'pending',
  'running',
  'passed',
  'failed',
  'blocked',
  'unavailable',
  'captcha',
  'auth',
};

Map<String, String> safeDiagnosticResults(Map<Object?, Object?>? response) => {
  for (final stage in diagnosticStages)
    stage: diagnosticStatuses.contains(response?[stage])
        ? response![stage] as String
        : 'unavailable',
};

String exportDiagnosticReport(Map<Object?, Object?> response) =>
    const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'scope': 'isolated-wdtt-connection',
      'results': safeDiagnosticResults(response),
    });
