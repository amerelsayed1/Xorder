import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:xorder_pos/data/postgres/pos_database.dart';

/// What the till TELLS an installer when the database will not open.
///
/// Each of these sends somebody to a different place: the DHCP reservation, the
/// firewall, `pg_hba.conf`, or a button on the screen they are already looking
/// at. Getting the class wrong does not just mislead — it sends a person to fix
/// something that was never broken.
void main() {
  group('classifying a database failure', () {
    test('a database that does not exist is a FIRST INSTALL, not a bad query', () {
      // The real message, verbatim from Postgres 16. This used to fall through
      // to `query` and render as "connected, but the database did not answer as
      // expected — check that xorder_pos is the right database", which is wrong
      // twice over: nothing answered, because nothing is there, and the remedy
      // is "First install on this machine" on the same screen. An installer
      // reading it goes checking a name that was right all along.
      expect(
        PosDbFailure.classify(
          'PostgreSQLSevereException FATAL 3D000: database "xorder_pos" does '
          'not exist',
        ),
        PosDbFailure.missingDatabase,
      );
    });

    test('a role that does not exist is its own problem, not a password', () {
      // Postgres phrases all three the same way — `database "x" does not
      // exist`, `role "x" does not exist`, `password authentication failed
      // for user "x"` — and this used to fold the middle one into `auth`. The
      // wizard then told an installer "PostgreSQL rejected «pos_admin» and
      // that password", which sent them to retype a password for a role
      // PostgreSQL had never heard of. Seen live on 26 Sep 2026, on a Mac
      // where PostgreSQL was installed by hand and only `postgres` exists.
      expect(
        PosDbFailure.classify('FATAL 28000: role "pos_till" does not exist'),
        PosDbFailure.missingRole,
      );
      expect(
        PosDbFailure.classify(
          'ServerException Severity.fatal 28000: role "pos_admin" does not '
          'exist',
        ),
        PosDbFailure.missingRole,
      );
    });

    test('the role in the message is read, not guessed', () {
      // A build connects as one role and grants to another, so the failing
      // role is not whichever one the step was holding.
      expect(
        PosDbException.roleNamedIn(
          'Severity.fatal 28000: role "pos_admin" does not exist',
        ),
        'pos_admin',
      );
      expect(PosDbException.roleNamedIn('nothing of the sort'), isNull);
    });

    test('a refused privilege is a GRANT problem, not a bad statement', () {
      // 42501. From PostgreSQL 15 the public schema no longer grants CREATE to
      // everyone, so a role that did not create the database cannot build
      // tables in it — which is what happens the moment a till is pointed at a
      // database somebody else made. "The statement failed" sends an installer
      // reading SQL; the remedy is a GRANT.
      expect(
        PosDbFailure.classify(
          'ServerException Severity.error 42501: permission denied for schema '
          'public',
        ),
        PosDbFailure.permissionDenied,
      );
    });

    test('a rejected password is auth, not a missing database', () {
      expect(
        PosDbFailure.classify(
          'FATAL 28P01: password authentication failed for user "pos_till"',
        ),
        PosDbFailure.auth,
      );
    });

    test('the transport failures keep their own answers', () {
      expect(
        PosDbFailure.classify('SocketException: Connection refused'),
        PosDbFailure.tcp,
      );
      expect(
        PosDbFailure.classify('SocketException: Failed host lookup: "till-01"'),
        PosDbFailure.dns,
      );
      expect(
        PosDbFailure.classify('HandshakeException: certificate verify failed'),
        PosDbFailure.tls,
      );
    });

    test('a refused secure connection is TLS, never a password or a cable', () {
      // The driver's words when the server answers the SSLRequest with `N`.
      expect(
        PosDbFailure.classify(
          'PgException: Server does not support SSL, but it was required '
          '(default configuration).',
        ),
        PosDbFailure.tls,
      );
      // PostgreSQL's words when a plaintext client meets a hostssl-only
      // pg_hba.conf. It says `pg_hba` too, and used to read as a password
      // problem — which sends an installer to retype a password that was
      // fine, when the remedy is encryption.
      expect(
        PosDbFailure.classify(
          'Severity.fatal 28000: no pg_hba.conf entry for host "192.168.1.31", '
          'user "pos_till", database "xorder_pos", no encryption',
        ),
        PosDbFailure.tls,
      );
      // …while an ENCRYPTED till from an address no line admits is still the
      // pg_hba problem it always was, whatever the word SSL in it suggests.
      expect(
        PosDbFailure.classify(
          'Severity.fatal 28000: no pg_hba.conf entry for host "203.0.113.9", '
          'user "pos_till", database "xorder_pos", SSL encryption',
        ),
        PosDbFailure.auth,
      );
    });

    test('a missing column is a failed statement, whatever it is called', () {
      // 42703, as a till reads it before the back-office door has run the
      // migration that adds the column. The message quotes the column's
      // name, and `password_hash` used to make this a refused LOGIN — the
      // till signed in fine; the statement asked for a column not there yet.
      expect(
        PosDbFailure.classify(
          const _ServerError(
            '42703',
            'column "password_hash" of relation "pos_staff" does not exist',
          ),
        ),
        PosDbFailure.query,
      );
      // Same shape, a different trap: `database` in a column's name used to
      // read as a first install.
      expect(
        PosDbFailure.classify(
          const _ServerError('42703', 'column "database_name" does not exist'),
        ),
        PosDbFailure.query,
      );
      expect(
        PosDbFailure.classify(
          const _ServerError('42P01', 'relation "pos_password_resets" does '
              'not exist'),
        ),
        PosDbFailure.query,
      );
    });

    test('the SQLSTATE decides where the server sent one', () {
      expect(
        PosDbFailure.classify(
          const _ServerError('28P01', 'password authentication failed for '
              'user "pos_till"'),
        ),
        PosDbFailure.auth,
      );
      expect(
        PosDbFailure.classify(
          const _ServerError('3D000', 'database "xorder_pos" does not exist'),
        ),
        PosDbFailure.missingDatabase,
      );
      expect(
        PosDbFailure.classify(
          const _ServerError('42501', 'permission denied for table '
              'pos_password_audit'),
        ),
        PosDbFailure.permissionDenied,
      );
    });

    test('28000 is left to the text, which tells its two meanings apart', () {
      // PostgreSQL sends 28000 for a missing role AND for a pg_hba refusal;
      // mapping the code alone would collapse them back into one answer.
      expect(
        PosDbFailure.classify(
          const _ServerError('28000', 'role "pos_till" does not exist'),
        ),
        PosDbFailure.missingRole,
      );
      expect(
        PosDbFailure.classify(
          const _ServerError(
            '28000',
            'no pg_hba.conf entry for host "192.168.1.31", user "pos_till", '
                'database "xorder_pos", no encryption',
          ),
        ),
        PosDbFailure.tls,
      );
    });

    test('anything unrecognised stays unknown rather than guessing', () {
      // The comment on `unknown` is a promise: never assume, report the raw
      // error alongside. A classifier that guessed here would be worse than one
      // that admitted it did not know.
      expect(
        PosDbFailure.classify('something nobody has seen before'),
        PosDbFailure.unknown,
      );
    });
  });
}

/// A server error as the driver raises it. Its constructor is private to the
/// driver, so this answers what `classify` asks — the SQLSTATE and the text —
/// and nothing else.
class _ServerError implements ServerException {
  const _ServerError(this.code, this.message);

  @override
  final String? code;

  @override
  final String message;

  @override
  String toString() => 'Severity.error $code: $message';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
