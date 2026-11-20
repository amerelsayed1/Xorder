import 'package:shared_module/app/password_sign_in.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';

/// Asks the platform whether a password belongs to a username in this till's
/// business, over the sign-in call setup already uses (`POST /api/auth/login`,
/// POS-BE-023). No new endpoint (tablet-cloud-onboarding, Stage 4).
///
/// The reply's token is a proof of the password and nothing more: it is
/// checked for presence and dropped, never stored, never used for another
/// call. The password is passed straight to the request and kept nowhere.
class CloudPasswordCheck implements PlatformPasswordCheck {
  CloudPasswordCheck({required this.api, required this.tenantSlug});

  final PosCloudApi api;
  final String tenantSlug;

  @override
  Future<PasswordVerdict> verify({
    required String username,
    required String password,
  }) async {
    final reply = await api.login(
      tenantSlug: tenantSlug,
      username: username,
      password: password,
    );
    if (reply.offline) return PasswordVerdict.unreachable;
    final status = reply.status;
    if (status == 429) return PasswordVerdict.throttled;
    if (reply.ok) {
      final token = reply.body['token'];
      return token is String && token.isNotEmpty
          ? PasswordVerdict.verified
          : PasswordVerdict.unreachable;
    }
    // Only these three are the platform's verdict on the credentials. Anything
    // else (a 5xx, a proxy's page, the wrong server) says nothing about the
    // password, so it must not be reported as a wrong one.
    return status == 401 || status == 403 || status == 422
        ? PasswordVerdict.rejected
        : PasswordVerdict.unreachable;
  }
}
