import 'package:dio/dio.dart';

import '../config/deployment.dart';
import 'network_log.dart';

/// Can this terminal actually reach *its* configured server?
///
/// Deliberately not "is there internet". An offline till on a LAN has no
/// internet and is perfectly healthy; a till with four bars of WiFi and a dead
/// database server is not. The only question that matters is whether our
/// endpoint answers.
abstract interface class ConnectivityProbe {
  Future<bool> canReach(DeploymentConfig config);
}

/// Accepts anything that parses as a resolvable endpoint. Used by the wizard
/// until the HTTP client is pointed at a real backend.
class FakeConnectivityProbe implements ConnectivityProbe {
  const FakeConnectivityProbe({this.reachable = true});

  final bool reachable;

  @override
  Future<bool> canReach(DeploymentConfig config) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    // Offline mode has no HTTP endpoint of its own — what has to answer is the
    // database, and `PosDatabase.probe` is what asks it.
    if (!config.mode.needsBaseUrl) return true;

    final uri = Uri.tryParse(config.baseUrl ?? '');
    if (uri == null || uri.host.isEmpty) return false;

    return reachable;
  }
}

/// Performs the small platform pulse check used by setup.
///
/// A setup screen that merely parses an address can promise a dead platform is
/// reachable, then fail only after the installer has completed.  This request
/// has a deliberately short timeout and does not attach a device token: it is
/// a reachability check, not a privileged API call.
class HttpConnectivityProbe implements ConnectivityProbe {
  HttpConnectivityProbe({Dio? client})
    : _client = client ??
          posHttpClient(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              validateStatus: (_) => true,
            ),
          );

  final Dio _client;

  @override
  Future<bool> canReach(DeploymentConfig config) async {
    if (!config.mode.needsBaseUrl) return true;
    final base = config.baseUrl;
    if (!DeploymentConfig.isPermittedPlatformUrl(base)) return false;
    final uri = Uri.parse(base!);
    final health = uri.replace(
      // The existing pulse route may answer 401 before a terminal is paired;
      // that still proves the configured platform is reachable.  We only need
      // to distinguish a live HTTP endpoint from a transport failure here.
      path: '${uri.path.replaceAll(RegExp(r'/+$'), '')}/api/dashboard/pulse',
      query: null,
      fragment: null,
    );
    try {
      final response = await _client.getUri<Object?>(health);
      return response.statusCode != null && response.statusCode! < 500;
    } on DioException {
      return false;
    }
  }
}
