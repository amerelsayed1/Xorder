import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/admin_mode_settings.dart';
import '../../../core/security/attempt_limiter.dart';
import '../../../core/security/pin_hash.dart';
import '../../../data/postgres/pos_database.dart';
import '../../../data/postgres/postgres_admin_repositories.dart'
    show isUndefinedColumn;
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
/// * **Entered** with a username and PASSWORD from somebody holding
///   [PosCapability.adminEnter] — asked here, not in a widget, so no screen can
///   open the back office by forgetting to ask. Somebody who has not chosen a
///   password yet (everybody, the day migration 55 runs) gets through once on
///   their PIN and is then held at [AdminMustSetPassword] until they choose
///   one: there is no way past it but [AdminSessionController.setPassword].
///   Every other door — the lock screen, the open-shift sign-in, the idle
///   unlock, the supervisor keypad, the forced reset — stays on the PIN, by
///   the owner's decision (25 Oct 2026).
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

/// Wrong username, wrong password, no password and a PIN that is not the
/// account's, a PIN typed for an account that has a password, or the right
/// person without the permission. One answer for all of them, so the door is
/// no way of finding out who may pass it — or who has set a password.
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

/// The PIN was right, for somebody who may enter and has no password yet.
///
/// **Not in.** Nothing of the back office is open, no entry is on the ledger,
/// and the only way on is [AdminSessionController.setPassword] — or back out
/// and start again. The PIN is accepted this once because it is the one
/// secret an upgraded account has; it is not accepted twice, because the
/// moment it has been used a password exists.
final class AdminMustSetPassword extends AdminSignIn {
  const AdminMustSetPassword();
}

/// The two entries of the new password differ.
final class AdminPasswordMismatch extends AdminSignIn {
  const AdminPasswordMismatch();
}

/// The new password breaks [PasswordPolicy].
final class AdminPasswordRejected extends AdminSignIn {
  const AdminPasswordRejected(this.problem);

  final PasswordProblem problem;
}

/// The database would not store the new password, for [refusal]. Still not
/// in, and still on the password step.
final class AdminPasswordNotSaved extends AdminSignIn {
  const AdminPasswordNotSaved(this.refusal);

  final AdminRefusal refusal;
}

/// The PIN step has gone — left too long, or Admin Mode was ended under it.
/// Start again from the username.
final class AdminPasswordStepExpired extends AdminSignIn {
  const AdminPasswordStepExpired();
}

/// What a technician's password reset came to.
sealed class TechnicianReset {
  const TechnicianReset();
}

/// [name]'s password is gone; they open Admin Mode with their PIN next and
/// choose a new one.
final class TechnicianResetDone extends TechnicianReset {
  const TechnicianResetDone(this.name);

  final String name;
}

/// The database password was right, and nobody active by that username has
/// a password to clear. Said plainly: whoever typed the database password
/// can read the staff table anyway, so there is nothing here to hide.
final class TechnicianResetNobody extends TechnicianReset {
  const TechnicianResetNobody();
}

/// PostgreSQL did not accept the typed database password. Counted against
/// Admin Mode's door, as a wrong password there is.
final class TechnicianResetDatabasePasswordRefused extends TechnicianReset {
  const TechnicianResetDatabasePasswordRefused();
}

final class TechnicianResetLockedOut extends TechnicianReset {
  const TechnicianResetLockedOut(this.wait);

  final Duration wait;
}

/// Nothing answered, or the database refused for another reason, or the
/// ledger would not take the row. Nothing was cleared.
final class TechnicianResetFailed extends TechnicianReset {
  const TechnicianResetFailed();
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
  const StaffVerified(this.staff, {this.mustSetPassword = false});

  final PosStaff staff;

  /// Got in on their PIN, at Admin Mode's door, with no password yet — see
  /// [AdminMustSetPassword]. Always false from [checkStaffPin].
  final bool mustSetPassword;
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

  return Authorization.check(staff, capability).isAllowed ||
          _ownerBeforeTheGrant(staff, capability)
      ? StaffVerified(staff)
      : StaffRefused(identified: staff);
}

/// Whether [username] and [secret] open Admin Mode's door (ADR-006b slice D).
///
/// **The shape of [secret] decides which it is checked as**, and nothing
/// about the account does. Four digits is a PIN — no password can be, since
/// a password is at least [PasswordPolicy.minLength] characters — and is
/// accepted only from somebody who has NOT set a password; anything else is a
/// password. Deciding from the account instead ("this person has a password,
/// so ask for it") would mean asking the database who has one before anybody
/// has proved who they are, and the door's question would leak the answer.
///
/// A PIN for an account that has a password is refused exactly as a wrong
/// password is, and names nobody: the PIN is no longer a key to Admin Mode
/// for that person, so typing it is a wrong guess, not a refusal to record.
///
/// **Checked in Dart against the stored hash** (the till role can read it);
/// moving the check into the database, so the hash is never readable by a
/// till, is slice E.
Future<StaffCheck> checkAdminSecret(
  SessionRepository sessions,
  StaffDirectoryRepository directory, {
  required String username,
  required String secret,
}) async {
  if (username.trim().isEmpty || secret.isEmpty) return const StaffRefused();

  if (PinRules.isWellFormed(secret)) {
    final check = await checkStaffPin(
      sessions,
      username: username,
      pin: secret,
      capability: PosCapability.adminEnter,
    );
    if (check is! StaffVerified) return check;
    final Set<int> holders;
    try {
      holders = await directory.withPassword();
    } on Object catch (error) {
      // Unknown is refused, never waved through on the PIN: letting a PIN in
      // because the password column could not be read would make an
      // unreadable column a way round every password.
      return error is PosDbException &&
              (error.failure == PosDbFailure.dns ||
                  error.failure == PosDbFailure.tcp)
          ? const StaffUnreachable()
          : const StaffRefused();
    }
    return holders.contains(check.staff.id)
        ? const StaffRefused()
        : StaffVerified(check.staff, mustSetPassword: true);
  }

  final PosStaff? staff;
  try {
    staff = await sessions.signInWithPassword(
      username: username.trim(),
      password: secret,
    );
  } on PosDbException catch (error) {
    return error.failure == PosDbFailure.dns || error.failure == PosDbFailure.tcp
        ? const StaffUnreachable()
        : const StaffRefused();
  }
  if (staff == null) return const StaffRefused();

  return Authorization.check(staff, PosCapability.adminEnter).isAllowed ||
          _ownerBeforeTheGrant(staff, PosCapability.adminEnter)
      ? StaffVerified(staff)
      : StaffRefused(identified: staff);
}

/// **The owner is let into Admin Mode before their role says so.**
///
/// Migration 46 is what gives the owner role `admin.enter`, and migrations run
/// at this door, after a sign-in — so on a database from before Admin Mode the
/// one person meant to hold the key could never turn it: refused for lacking
/// the grant, and the grant waiting on them getting in. Every existing install
/// met that wall on its first upgrade.
///
/// Only for this key and only for the owner: migration 42 fixes who the owner
/// is, and 46 grants them exactly this and nothing more. Once it has run the
/// role holds it and this is never the reason. Any other capability is asked
/// of the role as it stands.
bool _ownerBeforeTheGrant(PosStaff staff, String capability) =>
    PosCapability.canonical(capability) == PosCapability.adminEnter &&
    staff.isActive &&
    staff.role?.code == SystemRoles.ownerCode;

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

  /// Somebody whose PIN got them as far as [AdminMustSetPassword], and what
  /// they will need once they have chosen a password. Null otherwise.
  ///
  /// Held here, not in the widget, so the password step cannot be reached
  /// without the PIN step: [setPassword] has nothing to act on unless
  /// [signIn] put it here. It lasts no longer than Admin Mode's own
  /// inactivity timeout, and goes with [end], [cancelPasswordStep] and any
  /// new [signIn].
  _PasswordStep? _passwordStep;

  /// Five wrong tries, then the door shuts for thirty seconds doubling to
  /// fifteen minutes — [AttemptLimiter]'s rule, which began here and is now
  /// the lock screen's, the open-shift sign-in's and the supervisor keypad's
  /// too. Without it, the one door to everything took guesses as fast as
  /// somebody could type them.
  static const maxFailures = AttemptLimiter.defaultMaxFailures;

  /// Counted per terminal, not per username — every try is
  /// [AttemptLimiter.anyone] — so this door behaves exactly as it did before
  /// the rule was shared. Its own limiter rather than the till's sign-in one:
  /// a cashier's typos at the lock screen are no reason to shut the owner out
  /// of the back office, and the back office's five are on top of the till's.
  ///
  /// In memory, as the session is — a restart clears it, and restarting the
  /// till is not quiet or quick enough to be a way round it worth a file.
  /// Lazily built so the clock is read through [ref] at each try: a test moves
  /// [adminClockProvider]'s answer between them.
  ///
  /// Passwords are counted here too, on the same five, and so are wrong
  /// database passwords at the technician's reset. The owner's decision
  /// (25 Oct 2026) keeps this in-memory limiter rather than ADR-006b's
  /// `pos_auth_attempts` table: a persisted count is deferred until per-till
  /// roles (slice E) stop a till credential deleting its own lockout row.
  late final _limiter = AttemptLimiter(
    clock: () => ref.read(adminClockProvider)(),
  );

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

  /// Let [username] in, if [secret] is their password and they hold
  /// `admin.enter` — or hold them at [AdminMustSetPassword] if [secret] is
  /// their PIN and they have no password yet. See [checkAdminSecret].
  ///
  /// [databasePassword] is only for a till that has never kept the back
  /// office's database password — see [AdminNeedsDatabasePassword]. It is
  /// tried before it is kept, and kept only once it has got somebody in.
  Future<AdminSignIn> signIn({
    required String username,
    required String secret,
    String? databasePassword,
  }) async {
    // Everything from [ref] before the first await, by habit: the answer can
    // come back after the screen that asked has gone.
    final sessions = ref.read(sessionRepositoryProvider);
    final audit = ref.read(auditRepositoryProvider);
    final secrets = ref.read(adminDbSecretStoreProvider);
    final probe = ref.read(adminPasswordProbeProvider);
    final directory = ref.read(staffDirectoryRepositoryProvider);
    final door = _door();

    // A new try starts from the beginning: whatever PIN step was open is not
    // somebody else's to finish.
    _passwordStep = null;

    // Shut: answered before the secret is looked at, so a guess made while
    // the door is shut is not a guess at all.
    if (_limiter.lockedFor(AttemptLimiter.anyone) case final wait?) {
      return AdminSignInLockedOut(wait);
    }

    final PosStaff staff;
    final bool mustSetPassword;
    switch (await checkAdminSecret(
      sessions,
      directory,
      username: username,
      secret: secret,
    )) {
      case StaffUnreachable():
        return const AdminSignInUnreachable();
      case StaffRefused(:final identified):
        if (identified != null) {
          await _record(audit, identified, AuditAction.adminRefused);
        }
        return _refused(audit, directory, username);
      case StaffVerified(staff: final verified, mustSetPassword: final must):
        staff = verified;
        mustSetPassword = must;
    }

    // A secret that got somebody in clears the count and the backoff —
    // whether or not the database password below then works, because the
    // secret was not the problem.
    _limiter.succeed(AttemptLimiter.anyone);

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

    // Asked for the database password BEFORE the new one, not after: the
    // new password is written on the administrator connection, so a till
    // that cannot reach it would otherwise take a password it cannot keep.
    if (mustSetPassword) {
      _passwordStep = _PasswordStep(
        staff: staff,
        databasePassword: password,
        pin: secret,
        at: door.now(),
      );
      return const AdminMustSetPassword();
    }

    return _enter(door, staff, password, upgraded: false);
  }

  /// The second half of a first entry: [password], typed twice, becomes the
  /// person's Admin Mode password, and only then does Admin Mode open.
  ///
  /// **The schema upgrade runs first, here.** The column the password goes
  /// in is migration 55's, and the back-office door is what applies
  /// migrations to an installed till — so on the first entry after an
  /// upgrade it does not exist until this has run. If the upgrade fails and
  /// the password cannot be stored for that reason, the person is let in on
  /// the PIN this once, with the failure said above every pane, as a failed
  /// upgrade always is: Backup is behind this door, and a restaurant whose
  /// upgrade broke must still be able to reach it. Next time they are asked
  /// again.
  Future<AdminSignIn> setPassword({
    required String password,
    required String confirm,
  }) async {
    final door = _door();
    final step = _passwordStep;
    if (step == null ||
        !door.now().isBefore(step.at.add(door.timeout))) {
      _passwordStep = null;
      return const AdminPasswordStepExpired();
    }
    if (password != confirm) return const AdminPasswordMismatch();
    if (PasswordPolicy.validate(
          password,
          username: step.staff.username,
          pin: step.pin,
        )
        case final problem?) {
      return AdminPasswordRejected(problem);
    }

    // The write needs the administrator connection, and that exists only
    // while the credential is held — so it is held from here, and given back
    // below if this does not end inside. Management is still shut meanwhile:
    // its door is [state], which nothing here sets until the very end.
    door.credential.set(step.databasePassword);
    final directory = ref.read(staffDirectoryRepositoryProvider);

    var upgraded = true;
    if (door.upgrade case final upgrade?) {
      try {
        await upgrade();
        door.upgradeFailures.clear();
      } on Object catch (error) {
        upgraded = false;
        door.upgradeFailures.report('$error');
      }
    }

    AdminSignIn? failed;
    // Whether the write failed because migration 55's column is not there —
    // the one failure the PIN-only entry below exists for.
    var columnMissing = false;
    try {
      final refusal = (await directory.setOwnPassword(
        by: step.staff,
        password: password,
      )).refusal;
      // A refusal is an answer about this person — disabled since the PIN
      // step, say — and stands whether or not the upgrade ran.
      if (refusal != null) {
        door.credential.forget();
        return switch (refusal) {
          PasswordRejected(:final problem) => AdminPasswordRejected(problem),
          _ => AdminPasswordNotSaved(refusal),
        };
      }
    } on PosDbException catch (error) {
      columnMissing = isUndefinedColumn(error);
      failed =
          error.failure == PosDbFailure.dns || error.failure == PosDbFailure.tcp
          ? const AdminSignInUnreachable()
          : const AdminDatabaseRefused();
    } on Object catch (error) {
      columnMissing = isUndefinedColumn(error);
      failed = const AdminDatabaseRefused();
    }

    // A write that failed on a schema the upgrade could not bring up is the
    // one failure that lets them in — see above. Any other is said, and
    // they stay on this step with the credential given back.
    //
    // **Both halves, asked of the SQLSTATE.** "The upgrade failed" alone let
    // anything through once it had: a dropped connection or a refused grant
    // on the write opened Admin Mode on four digits, the exact door slice D
    // closed. A missing column is the only failure that says the password
    // has nowhere to go yet, rather than that something is wrong.
    if (failed != null && (upgraded || !columnMissing)) {
      door.credential.forget();
      return failed;
    }

    _passwordStep = null;
    return _enter(door, step.staff, step.databasePassword, upgraded: true);
  }

  /// Back out of the password step. The PIN that reached it is spent: the
  /// next try starts again from the username.
  void cancelPasswordStep() => _passwordStep = null;

  /// The technician's reset of [username]'s password — the owner's included,
  /// which nobody can clear from Management ([OwnerPasswordIsTheirs]).
  ///
  /// **The proof is the database password, typed.** Not the one this till
  /// keeps: anybody at the till could use that, and then choose the owner's
  /// new password with the owner's four-digit PIN. A technician who knows
  /// the administrator's database password can already change any row with
  /// psql; this only saves them the psql, and writes the ledger row psql
  /// would not.
  ///
  /// Wrong database passwords count against this door's own five, so the
  /// reset is no way of guessing the database password at leisure.
  Future<TechnicianReset> technicianClearPassword({
    required String username,
    required String databasePassword,
  }) async {
    final probe = ref.read(adminPasswordProbeProvider);
    final reset = ref.read(technicianPasswordResetProvider);

    if (_limiter.lockedFor(AttemptLimiter.anyone) case final wait?) {
      return TechnicianResetLockedOut(wait);
    }
    if (username.trim().isEmpty || databasePassword.isEmpty) {
      return const TechnicianResetNobody();
    }

    final failure = await probe(databasePassword);
    if (failure == PosDbFailure.auth) {
      return switch (_limiter.fail(AttemptLimiter.anyone)) {
        AttemptRefused() => const TechnicianResetDatabasePasswordRefused(),
        AttemptLockedOut(:final wait) => TechnicianResetLockedOut(wait),
      };
    }
    if (failure != null) return const TechnicianResetFailed();
    _limiter.succeed(AttemptLimiter.anyone);

    try {
      final result = await reset(
        username: username,
        databasePassword: databasePassword,
      );
      if (result.refusal != null) return const TechnicianResetFailed();
      final name = result.value;
      return name == null
          ? const TechnicianResetNobody()
          : TechnicianResetDone(name);
    } on Object {
      return const TechnicianResetFailed();
    }
  }

  /// In: the ledger row, the credential, the upgrade unless it has run, and
  /// last the session — which is what opens Management.
  Future<AdminSignIn> _enter(
    _Door door,
    PosStaff staff,
    String password, {
    required bool upgraded,
  }) async {
    // The ledger first: no row, no entry.
    final started = door.now();
    try {
      await door.audit.record(
        by: staff,
        action: AuditAction.adminEntered,
        entityType: AuditAction.entityAdminSession,
        entityId: '${staff.id}',
      );
    } on Object {
      // The password step holds the credential already; an entry that did
      // not happen must not leave it held.
      door.credential.forget();
      return const AdminSignInUnreachable();
    }

    door.credential.set(password);

    // Whatever migrations this build carries and the database lacks — see
    // `schemaUpgraderProvider` for why at the door. After the credential,
    // because the upgrade runs on it; before [state], because the session is
    // what lets Management past its door, and a pane that loaded first would
    // read a table the upgrade was about to create. A failure is said above
    // every pane and does not keep anybody out: Backup is in here.
    if (!upgraded && door.upgrade != null) {
      try {
        await door.upgrade!();
        door.upgradeFailures.clear();
      } on Object catch (error) {
        door.upgradeFailures.report('$error');
      }
    }

    _lastActivity = started;
    state = AdminSession(staff: staff, startedAt: started);
    return const AdminSignedIn();
  }

  /// What the door needs from [ref], read in one go before anything awaits.
  _Door _door() => _Door(
    audit: ref.read(auditRepositoryProvider),
    credential: ref.read(adminDbCredentialProvider.notifier),
    upgrade: ref.read(schemaUpgraderProvider),
    upgradeFailures: ref.read(schemaUpgradeFailureProvider.notifier),
    now: ref.read(adminClockProvider),
    timeout: ref.read(adminModeSettingsProvider).timeout,
  );

  /// One more wrong try at this terminal, and the door shut if it was one too
  /// many. The count moves before the first await, so two submits racing each
  /// other cannot both be the fourth.
  Future<AdminSignIn> _refused(
    AuditRepository audit,
    StaffDirectoryRepository directory,
    String username,
  ) async {
    final Duration wait;
    switch (_limiter.fail(AttemptLimiter.anyone)) {
      case AttemptRefused(:final attemptsLeft):
        return AdminSignInRefused(attemptsLeft);
      case AttemptLockedOut(wait: final shut):
        wait = shut;
    }

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
    _passwordStep = null;
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

/// See [AdminSessionController._passwordStep].
class _PasswordStep {
  const _PasswordStep({
    required this.staff,
    required this.databasePassword,
    required this.pin,
    required this.at,
  });

  final PosStaff staff;
  final String databasePassword;

  /// Kept only so the new password can be refused for being the same.
  final String pin;
  final DateTime at;
}

class _Door {
  const _Door({
    required this.audit,
    required this.credential,
    required this.upgrade,
    required this.upgradeFailures,
    required this.now,
    required this.timeout,
  });

  final AuditRepository audit;
  final AdminDbCredential credential;
  final Future<List<int>> Function()? upgrade;
  final SchemaUpgradeFailure upgradeFailures;
  final DateTime Function() now;
  final Duration timeout;
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
