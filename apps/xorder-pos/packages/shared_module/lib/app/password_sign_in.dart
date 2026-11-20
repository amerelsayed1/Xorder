import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/shift.dart';
import 'providers.dart';

/// What the platform said about a username and password.
enum PasswordVerdict { verified, rejected, unreachable, throttled }

/// Asks the platform whether a password belongs to a username in this till's
/// business (tablet-cloud-onboarding, Stage 4).
///
/// **The password is a question, never a possession.** It goes to the platform
/// in the one request this makes and is not kept: not in memory past the call,
/// not in a file, not in a log. The platform's token reply is discarded by the
/// implementation; only the verdict comes back.
///
/// Null in every app that has no platform to ask (the offline app, every test
/// that does not bind one) — see [platformPasswordCheckProvider].
abstract interface class PlatformPasswordCheck {
  Future<PasswordVerdict> verify({
    required String username,
    required String password,
  });
}

/// The shared default: nothing to ask. The cloud app binds the real one.
final platformPasswordCheckProvider = Provider<PlatformPasswordCheck?>(
  (ref) => null,
);

/// How a password sign-in ended.
sealed class PasswordSignInResult {
  const PasswordSignInResult();
}

/// The platform accepted the password and this till has that person on its
/// staff list, active. Their permissions are the ones the till already holds
/// for them; nothing is fetched or changed.
final class PasswordSignedIn extends PasswordSignInResult {
  const PasswordSignedIn(this.staff);
  final PosStaff staff;
}

/// A wrong password, an unknown name: one answer, so the screen says nothing
/// about which usernames exist.
final class PasswordRefused extends PasswordSignInResult {
  const PasswordRefused();
}

/// The platform accepted the password but this till's staff list does not have
/// the person (added on the dashboard a moment ago, or no longer active). The
/// platform's say-so alone does not open a till.
final class PasswordAccountNotOnTill extends PasswordSignInResult {
  const PasswordAccountNotOnTill();
}

final class PasswordUnreachable extends PasswordSignInResult {
  const PasswordUnreachable();
}

final class PasswordThrottled extends PasswordSignInResult {
  const PasswordThrottled();
}

/// Password sign-in: the platform verifies, the till decides.
///
/// Signing in is still a local act on a local person: the platform confirms
/// the password, then the till looks the username up among its own active
/// staff and signs that person in with what it already cached (BR-8). A
/// person the platform knows and the till does not is not signed in.
class PasswordSignIn {
  PasswordSignIn({required this.check, required this.roster});

  final PlatformPasswordCheck check;
  final Future<List<PosStaff>> Function() roster;

  Future<PasswordSignInResult> signIn({
    required String username,
    required String password,
  }) async {
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) return const PasswordRefused();

    final verdict = await check.verify(username: name, password: password);
    switch (verdict) {
      case PasswordVerdict.unreachable:
        return const PasswordUnreachable();
      case PasswordVerdict.throttled:
        return const PasswordThrottled();
      case PasswordVerdict.rejected:
        return const PasswordRefused();
      case PasswordVerdict.verified:
        break;
    }

    final wanted = name.toLowerCase();
    for (final person in await roster()) {
      if (person.username?.trim().toLowerCase() == wanted) {
        return PasswordSignedIn(person);
      }
    }
    return const PasswordAccountNotOnTill();
  }
}

/// Null when this app has no platform to ask, which is also when the lock
/// screen offers the PIN alone.
final passwordSignInProvider = Provider<PasswordSignIn?>((ref) {
  final check = ref.watch(platformPasswordCheckProvider);
  if (check == null) return null;
  return PasswordSignIn(
    check: check,
    roster: () =>
        ref.read(staffDirectoryRepositoryProvider).all(includeInactive: false),
  );
});
