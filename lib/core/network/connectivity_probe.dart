import '../config/deployment.dart';

/// Can this terminal actually reach *its* configured server?
///
/// Deliberately not "is there internet". A branch till on an islanded LAN has no
/// internet and is perfectly healthy; a till with four bars of WiFi and a dead
/// branch server is not. The only question that matters is whether our endpoint
/// answers.
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

    if (config.mode == DeploymentMode.standalone) return true;

    final uri = Uri.tryParse(config.baseUrl ?? '');
    if (uri == null || uri.host.isEmpty) return false;

    return reachable;
  }
}
