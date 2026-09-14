import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/admin_mode_settings.dart';
import '../../../data/postgres/pos_database.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/authorization.dart';

/// Admin Mode: the back office as a session somebody is *in*.
///
/// **It used to be a state the till drifted into.** Management opened for
/// whoever was signed in at the till once the database administrator password
/// was held, and nothing ever let go of that password — not leaving the back
/// office, not locking the till. So after a manager had used it once, F8 at a
/// locked till opened the staff screen for whoever pressed it. See
/// `test/features/admin_entry_test.dart`.
///
/// Now it has a start, a person, and an end:
///
/// * **Entered** with a username and PIN from somebody holding
///   [PosCapability.adminEnter] — asked here, not in a widget, so no screen can
///   open the back office by forgetting to ask.
/// * **Separate from the till.** Entering does not change who is signed in at
///   the till, and leaving hands the till back to them as it was.
/// * **Ended** by Exit, by the till being locked or left, and by the inactivity
///   timeout in [AdminModeSettings] — and ending forgets the administrator's
///   database credential, which is what the back office's writes run on.
class AdminSession {
  const AdminSession({required this.staff, required this.startedAt});

  /// Who is in. Not the till's operator: see [AdminSessionController].
  final PosStaff staff;
  final DateTime startedAt;
}

/// How a session ended. The audit row says which.
enum AdminSessionEnd {
  /// The Exit Admin Mode button.
  exited,

  /// Nobody touched it for the configured time.
  timedOut,

  /// The screen went away some other way — the till was locked, another screen
  /// was opened from the bar. Ended exactly as Exit ends it.
  left,
}

/// What a sign-in came to. Data, not exceptions — the same reasoning as
/// `AdminRefusal`: every one of these is an ordinary thing to happen at a door.
sealed class AdminSignIn {
  const AdminSignIn();
}

final class AdminSignedIn extends AdminSignIn {
  const AdminSignedIn();
}

/// Wrong username, wrong PIN, or the right person without the permission. One
/// answer for all three, so the door is no way of finding out who may pass it.
final class AdminSignInRefused extends AdminSignIn {
  const AdminSignInRefused(this.attemptsLeft);

  /// Before this terminal shuts the door — see [AdminSignInLockedOut].
  final int attemptsLeft;
}

/// Too many wrong tries in a row at this terminal. Nothing is checked — not
/// even a right PIN — until [wait] has passed.
final class AdminSignInLockedOut extends AdminSignIn {
  const AdminSignInLockedOut(this.wait);

  final Duration wait;
}

/// The branch database did not answer, or the audit ledger could not record
/// the entry. Either way nothing in Admin Mode would work, and an entry the
/// ledger cannot see is the one thing this session exists not to be.
final class AdminSignInUnreachable extends AdminSignIn {
  const AdminSignInUnreachable();
}

/// The right person, on a till that has never kept the back-office database
/// password — every install from before Admin Mode. Asked once, then kept.
final class AdminNeedsDatabasePassword extends AdminSignIn {
  const AdminNeedsDatabasePassword();
}

/// The database password typed alongside the PIN was wrong.
final class AdminDatabasePasswordRefused extends AdminSignIn {
  const AdminDatabasePasswordRefused();
}

/// Connected, and the database refused the administrator for some other reason
/// — TLS, a missing database, a role with no rights to it.
final class AdminDatabaseRefused extends AdminSignIn {
  const AdminDatabaseRefused();
}

/// Who a username and PIN name, and whether they may do a thing.
sealed class StaffCheck {
  const StaffCheck();
}

final class StaffVerified extends StaffCheck {
  const StaffVerified(this.staff);

  final PosStaff staff;
}

/// Refused. [identified] is the person when the username and PIN were right
/// and only the permission was missing — the one refusal with a name to put on
/// an audit row.
final class StaffRefused extends StaffCheck {
  const StaffRefused({this.identified});

  final PosStaff? identified;
}

/// Nothing answered, so nobody could be checked.
final class StaffUnreachable extends StaffCheck {
  const StaffUnreachable();
}

/// Whether [username] and [pin] name an active member of staff who holds
/// [capability].
///
/// **One answer, shared.** Admin Mode asks it for `admin.enter`; the forced
/// terminal reset asks it for `terminal.manage` before it wipes a working till.
/// It takes the repository rather than a `WidgetRef` so that nothing here can
/// read a widget that has gone by the time the database answers — the crash
/// the back-office door had once already.
///
/// Username AND PIN, through [SessionRepository.signInAs], never a PIN alone: a
/// PIN approves one refund somebody is standing over, and is not enough to
/// take the back office.
Future<StaffCheck> checkStaffPin(
  SessionRepository sessions, {
  required String username,
  required String pin,
  required String capability,
}) async {
  if (username.trim().isEmpty || pin.isEmpty) return const StaffRefused();

  final PosStaff? staff;
  try {
    staff = await sessions.signInAs(username: username.trim(), pin: pin);
  } on PosDbException catch (error) {
    // Nothing answered — separate from a refusal because the forced reset
    // exists to rescue exactly this till. Anything else is refused: a database
    // that answered and failed has not said who this is.
    return error.failure == PosDbFailure.dns || error.failure == PosDbFailure.tcp
        ? const StaffUnreachable()
        : const StaffRefused();
  }
  if (staff == null) return const StaffRefused();

  return Authorization.check(staff, capability).isAllowed
      ? StaffVerified(staff)
      : StaffRefused(identified: staff);
}

/// The clock Admin Mode's timeout is measured with. A provider so a test can
/// move it instead of waiting five minutes.
final adminClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The session, or null outside Admin Mode.
///
/// **The last activity is not part of the state.** A pointer moving across a
/// list touches it many times a second, and every state change rebuilds every
/// screen watching this — so it is a field the inactivity watch asks for, not
/// a value anybody is notified of.
class AdminSessionController extends Notifier<AdminSession?> {
  DateTime? _lastActivity;

  /// Five wrong tries, then the door shuts — the supervisor keypad's number,
  /// and for its reason: enough that a manager mistyping under pressure is not
  /// shut out, few enough that the door is not a way to walk a four-digit
  /// space. Without it, the one door to everything took guesses as fast as
  /// somebody could type them.
  static const maxFailures = 5;

  /// The first wait, doubled for every lockout since the last PIN that got
  /// somebody in, up to [longestLockout]. Thirty seconds is nothing to an
  /// owner who fat-fingered it; doubling makes the ten thousand PINs a matter
  /// of weeks rather than an afternoon.
  static const firstLockout = Duration(seconds: 30);

  /// Capped, because this also shuts out the owner, and a door locked for a
  /// day on a Friday night is a restaurant that cannot close its shift.
  static const longestLockout = Duration(minutes: 15);

  /// Counted per terminal, not per username: counting per username would
  /// let somebody walk the PINs by trying every name in turn. In memory, as
  /// the session is — a restart clears it, and restarting the till is not
  /// quiet or quick enough to be a way round it worth a file.
  int _failures = 0;
  int _lockouts = 0;
  DateTime? _lockedUntil;

  static Duration _lockoutFor(int lockouts) {
    var wait = firstLockout;
    for (var i = 1; i < lockouts && wait < longestLockout; i++) {
      wait *= 2;
    }
    return wait > longestLockout ? longestLockout : wait;
  }

  /// False once the container holding this is gone. Management ends the
  /// session a moment after its screen goes away, and on the app's way down —
  /// or a test's — that moment can come after the container: there is nothing
  /// left to end, and reading [state] then would throw into whatever runs
  /// next.
  bool _alive = false;

  @override
  AdminSession? build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return null;
  }

  /// When the session locks if nobody touches it again, or null without one.
  DateTime? get locksAt {
    final last = _lastActivity;
    if (state == null || last == null) return null;
    return last.add(ref.read(adminModeSettingsProvider).timeout);
  }

  bool get isIdle {
    final at = locksAt;
    return at != null && !ref.read(adminClockProvider)().isBefore(at);
  }

  /// Somebody is still there.
  void touch() {
    if (state != null) _lastActivity = ref.read(adminClockProvider)();
  }

  /// Let [username] in, if their [pin] is right and they hold `admin.enter`.
  ///
  /// [databasePassword] is only for a till that has never kept the back
  /// office's database password — see [AdminNeedsDatabasePassword]. It is
  /// tried before it is kept, and kept only once it has got somebody in.
  Future<AdminSignIn> signIn({
    required String username,
    required String pin,
    String? databasePassword,
  }) async {
    // Everything from [ref] before the first await, by habit: the answer can
    // come back after the screen that asked has gone.
    final sessions = ref.read(sessionRepositoryProvider);
    final audit = ref.read(auditRepositoryProvider);
    final secrets = ref.read(adminDbSecretStoreProvider);
    final probe = ref.read(adminPasswordProbeProvider);
    final credential = ref.read(adminDbCredentialProvider.notifier);
    final directory = ref.read(staffDirectoryRepositoryProvider);
    final upgrade = ref.read(schemaUpgraderProvider);
    final upgradeFailures = ref.read(schemaUpgradeFailureProvider.notifier);
    final now = ref.read(adminClockProvider);

    // Shut: answered before the PIN is looked at, so a guess made while the
    // door is shut is not a guess at all.
    if (_lockedUntil case final until?) {
      final wait = until.difference(now());
      if (wait > Duration.zero) return AdminSignInLockedOut(wait);
      _lockedUntil = null;
    }

    final PosStaff staff;
    switch (await checkStaffPin(
      sessions,
      username: username,
      pin: pin,
      capability: PosCapability.adminEnter,
    )) {
      case StaffUnreachable():
        return const AdminSignInUnreachable();
      case StaffRefused(:final identified):
        if (identified != null) {
          await _record(audit, identified, AuditAction.adminRefused);
        }
        return _refused(audit, directory, username, now());
      case StaffVerified(staff: final verified):
        staff = verified;
    }

    // A PIN that got somebody in clears the count and the backoff — whether
    // or not the database password below then works, because the PIN was not
    // the problem.
    _failures = 0;
    _lockouts = 0;
    _lockedUntil = null;

    final typed = databasePassword ?? '';
    String? password = typed;
    if (typed.isEmpty) {
      try {
        password = await secrets.read();
      } on Object {
        password = null;
      }
    }
    if (password == null || password.isEmpty) {
      return const AdminNeedsDatabasePassword();
    }

    // Tried every time, kept one or typed one. A kept password that has stopped
    // working — somebody changed the database's — is asked for again rather
    // than refusing the owner forever with a message about their PIN.
    final failure = await probe(password);
    if (failure == PosDbFailure.dns || failure == PosDbFailure.tcp) {
      return const AdminSignInUnreachable();
    }
    if (failure == PosDbFailure.auth) {
      return typed.isEmpty
          ? const AdminNeedsDatabasePassword()
          : const AdminDatabasePasswordRefused();
    }
    if (failure != null) return const AdminDatabaseRefused();

    if (typed.isNotEmpty) {
      try {
        await secrets.write(typed);
      } on Object {
        // It still works for this session; the next one asks again, which is
        // the honest outcome of a store that would not take it.
      }
    }

    // The ledger first: no row, no entry.
    final started = now();
    try {
      await audit.record(
        by: staff,
        action: AuditAction.adminEntered,
        entityType: AuditAction.entityAdminSession,
        entityId: '${staff.id}',
      );
    } on Object {
      return const AdminSignInUnreachable();
    }

    credential.set(password);

    // Whatever migrations this build carries and the database lacks — see
    // `schemaUpgraderProvider` for why at the door. After the credential,
    // because the upgrade runs on it; before [state], because the session is
    // what lets Management past its door, and a pane that loaded first would
    // read a table the upgrade was about to create. A failure is said above
    // every pane and does not keep anybody out: Backup is in here.
    if (upgrade != null) {
      try {
        await upgrade();
        upgradeFailures.clear();
      } on Object catch (error) {
        upgradeFailures.report('$error');
      }
    }

    _lastActivity = started;
    state = AdminSession(staff: staff, startedAt: started);
    return const AdminSignedIn();
  }

  /// One more wrong try at this terminal, and the door shut if it was one too
  /// many. The count moves before the first await, so two submits racing each
  /// other cannot both be the fourth.
  Future<AdminSignIn> _refused(
    AuditRepository audit,
    StaffDirectoryRepository directory,
    String username,
    DateTime at,
  ) async {
    _failures++;
    if (_failures < maxFailures) {
      return AdminSignInRefused(maxFailures - _failures);
    }
    _failures = 0;
    _lockouts++;
    final wait = _lockoutFor(_lockouts);
    _lockedUntil = at.add(wait);

    // Against whoever the username names, because the ledger's every row has
    // somebody on it and a guessed-at account is the thing worth reading
    // about. A username that names nobody leaves no row: there is no one to
    // put it against, and the audit table is not the place to invent one.
    if (await _named(directory, username) case final named?) {
      await _record(
        audit,
        named,
        AuditAction.adminLockedOut,
        after: {'wrong_pins': maxFailures, 'locked_seconds': wait.inSeconds},
      );
    }
    return AdminSignInLockedOut(wait);
  }

  static Future<PosStaff?> _named(
    StaffDirectoryRepository directory,
    String username,
  ) async {
    final wanted = username.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    try {
      for (final person in await directory.all(includeInactive: false)) {
        if (person.username?.toLowerCase() == wanted) return person;
      }
    } on Object {
      // Unreadable is nobody. The lockout stands either way.
    }
    return null;
  }

  /// Leave Admin Mode. Safe to call when not in it.
  ///
  /// The credential and the state go **before** the audit write, so the lock is
  /// never waiting on a database that may not answer: a back office that stays
  /// open because the ledger is slow is the failure this exists to prevent.
  Future<void> end(AdminSessionEnd how) async {
    if (!_alive) return;
    final session = state;
    if (session == null) return;
    final audit = ref.read(auditRepositoryProvider);

    ref.read(adminDbCredentialProvider.notifier).forget();
    _lastActivity = null;
    state = null;

    await _record(
      audit,
      session.staff,
      how == AdminSessionEnd.timedOut
          ? AuditAction.adminTimedOut
          : AuditAction.adminExited,
      after: {'how': how.name},
    );
  }

  static Future<void> _record(
    AuditRepository audit,
    PosStaff by,
    String action, {
    Map<String, Object?>? after,
  }) async {
    try {
      await audit.record(
        by: by,
        action: action,
        entityType: AuditAction.entityAdminSession,
        entityId: '${by.id}',
        after: after,
      );
    } on Object {
      // Leaving and refusing must happen whether or not the ledger answers.
    }
  }
}

final adminSessionProvider =
    NotifierProvider<AdminSessionController, AdminSession?>(
      AdminSessionController.new,
    );

/// This till's Admin Mode settings, as saved.
class AdminModeSettingsController extends Notifier<AdminModeSettings> {
  @override
  AdminModeSettings build() =>
      ref.watch(terminalBootProvider).config?.adminMode ??
      AdminModeSettings.standard;

  /// In force now, and in `config.json` for the next launch — the same
  /// read-modify-write the printer settings use. False when the file could not
  /// be written, so the screen can say the change will not survive a restart.
  Future<bool> save(AdminModeSettings settings) async {
    state = settings;
    try {
      final store = ref.read(terminalConfigStoreProvider);
      final saved = await store.read();
      if (saved != null) await store.write(saved.copyWith(adminMode: settings));
      return true;
    } on Object {
      return false;
    }
  }
}

final adminModeSettingsProvider =
    NotifierProvider<AdminModeSettingsController, AdminModeSettings>(
      AdminModeSettingsController.new,
    );
