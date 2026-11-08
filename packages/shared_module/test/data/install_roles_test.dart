import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';

/// The three accounts a Windows install creates, as the SQL that creates them.
///
/// Worth pinning without a database: `CREATE ROLE` takes no bind parameters,
/// so each password is spliced into the statement as a literal — and the one
/// thing that literal must never do is end early.
void main() {
  test('the administrator creates databases and nothing more', () {
    final sql = LocalBootstrap.roleStatements(
      InstallRole.admin,
      'pos_admin',
      'secret',
    );
    expect(sql, ['CREATE ROLE "pos_admin" LOGIN CREATEDB PASSWORD \'secret\'']);
    expect(sql.join(), isNot(contains('SUPERUSER')));
    expect(sql.join(), isNot(contains('CREATEROLE')));
  });

  test('the till gets a login and waits for its table grants', () {
    expect(
      LocalBootstrap.roleStatements(InstallRole.till, 'pos_till', 'p'),
      ['CREATE ROLE "pos_till" LOGIN PASSWORD \'p\''],
    );
  });

  test('the backup account reads everything and is granted nothing else', () {
    expect(
      LocalBootstrap.roleStatements(InstallRole.backup, 'pos_backup', 'p'),
      [
        'CREATE ROLE "pos_backup" LOGIN PASSWORD \'p\'',
        'GRANT pg_read_all_data TO "pos_backup"',
      ],
    );
  });

  test('a quote in a password is doubled, so the literal cannot end early',
      () {
    final sql = LocalBootstrap.roleStatements(
      InstallRole.till,
      'pos_till',
      "it's'; DROP ROLE postgres; --",
    ).single;
    expect(
      sql,
      "CREATE ROLE \"pos_till\" LOGIN PASSWORD 'it''s''; DROP ROLE postgres; --'",
    );
  });

  test('a role name that is not a plain identifier is refused', () {
    expect(
      () => LocalBootstrap.roleStatements(
        InstallRole.till,
        'pos_till"; DROP ROLE x; --',
        'p',
      ),
      throwsArgumentError,
    );
  });

  test('the names an install uses', () {
    expect(InstallRole.defaultNames, {
      InstallRole.admin: 'pos_admin',
      InstallRole.till: 'pos_till',
      InstallRole.backup: 'pos_backup',
    });
  });
}
