import 'package:flutter_test/flutter_test.dart';
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
