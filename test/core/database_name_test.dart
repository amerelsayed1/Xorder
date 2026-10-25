import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';

/// The database the wizard builds is named after the restaurant it serves.
void main() {
  test('a slug becomes a plain identifier ending in _db', () {
    expect(DeploymentConfig.databaseNameFor('demo'), 'demo_db');
    expect(DeploymentConfig.databaseNameFor('good-cafe'), 'good_cafe_db');
    expect(DeploymentConfig.databaseNameFor('Al Asima.Grill'), 'al_asima_grill_db');
    // PostgreSQL identifiers cannot start with a digit.
    expect(DeploymentConfig.databaseNameFor('7eleven'), 't_7eleven_db');
    expect(DeploymentConfig.databaseNameFor('--demo--'), 'demo_db');
  });

  test('every name it produces is one CREATE DATABASE will take', () {
    for (final slug in ['demo', 'good-cafe', 'x', '99', 'كافيه', 'a--b']) {
      final name = DeploymentConfig.databaseNameFor(slug);
      expect(DeploymentConfig.isPlainIdentifier(name), isTrue, reason: slug);
    }
  });

  test('no restaurant yet means the old shared default', () {
    expect(DeploymentConfig.databaseNameFor(null), 'xorder_pos');
    expect(DeploymentConfig.databaseNameFor(''), 'xorder_pos');
    // A slug with nothing an identifier can keep falls back the same way.
    expect(DeploymentConfig.databaseNameFor('كافيه'), 'xorder_pos');
  });
}
