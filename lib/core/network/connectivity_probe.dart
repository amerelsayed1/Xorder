import '../config/deployment.dart';

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
