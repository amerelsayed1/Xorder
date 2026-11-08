/// The rules for what the PostgreSQL test suites leave behind, and which of it
/// `tool/drop_test_databases.dart` may drop.
///
/// Pure Dart with no I/O, so the rules are unit-tested without a database
/// (`test/tool/test_db_cleanup_test.dart`). Dropping a database cannot be
/// undone, so every decision is an exact match on a name built the way
/// `test/data/pg_fixture.dart` builds it, never a loose `LIKE 'xorder_pos%'`:
/// the real till database is called `xorder_pos` and must never be a match.
library;

/// A short, stable tag for a working copy: FNV-1a of its absolute path, eight
/// hex digits. **Must equal `PgFixture`'s tag**; the test compares the two, so
/// changing one without the other fails.
String checkoutTag(String path) {
  var hash = 0x811c9dc5;
  for (final unit in path.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

final _tagShape = RegExp(r'^[0-9a-f]{8}$');

/// Whether [tag] has the shape of a checkout tag. The script refuses anything
/// else, so a typo can never widen the match.
bool isCheckoutTag(String tag) => _tagShape.hasMatch(tag);

/// A database the test suites create for the checkout with [tag]:
/// `xorder_pos_<suite>_<tag>`, with a non-empty suite (which includes the shared
/// `xorder_pos_test_<tag>`). Never `xorder_pos` itself, never another tag.
bool isTestDatabase(String name, String tag) {
  if (!isCheckoutTag(tag)) return false;
  return RegExp('^xorder_pos_[a-z0-9_]+_$tag\$').hasMatch(name);
}

/// A role the suites create for the checkout with [tag]:
/// `xorder_test_<name>_<tag>` (`PgFixture.roleFor`).
bool isTestRole(String name, String tag) {
  if (!isCheckoutTag(tag)) return false;
  return RegExp('^xorder_test_[a-z0-9_]+_$tag\$').hasMatch(name);
}

/// Hosts that are this machine. The script drops databases, so it does not do
/// it on a server somebody else may be using unless told to.
bool isLocalHost(String host) {
  final h = host.trim().toLowerCase();
  return h == '127.0.0.1' || h == 'localhost' || h == '::1' || h == '[::1]';
}

/// A name that is safe to put inside double quotes in a statement. Everything
/// the matchers above accept already is; this is the second lock.
bool isPlainIdentifier(String name) =>
    RegExp(r'^[a-z0-9_]{1,63}$').hasMatch(name);
