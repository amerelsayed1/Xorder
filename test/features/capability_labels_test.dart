import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';

/// Every permission an owner can tick says what it means.
///
/// **Written because `purchase.manage` did not.** `AdminText.capability` ends in
/// a `_ => capability` fall-through — deliberately, so a capability from a newer
/// build is shown rather than hidden — and the effect on a capability from *this*
/// build is that the Roles pane renders the raw string `purchase.manage` to a
/// restaurant owner. The comment above that switch says the quiet part out loud:
/// "the capability name is not shown on its own anywhere", and then nothing
/// checked.
///
/// Both languages, because a role screen is ticked by whoever runs the
/// restaurant and half of them are working in Arabic.
void main() {
  const languages = <String, AppStrings>{'en': EnStrings(), 'ar': ArStrings()};

  for (final entry in languages.entries) {
    group('in ${entry.key}', () {
      final strings = entry.value;

      test('every capability has a sentence, not a key', () {
        final unlabelled = <String>[];
        for (final capability in PosCapability.all) {
          final label = AdminText.capability(strings, capability);
          // The fall-through returns the key itself, which is the failure this
          // catches. Anything else is a translation somebody wrote.
          if (label == capability) unlabelled.add(capability);
        }

        expect(
          unlabelled,
          isEmpty,
          reason:
              'These render as raw keys in the Roles pane. Add a case to '
              'AdminText.capability and a string in both languages.',
        );
      });

      test('and it reads as a sentence rather than a code', () {
        // A label somebody pasted the key into would pass the check above.
        for (final capability in PosCapability.all) {
          final label = AdminText.capability(strings, capability);
          expect(label, isNot(contains('.')), reason: capability);
          expect(label.trim(), isNotEmpty, reason: capability);
        }
      });

      test('every capability group has a name', () {
        for (final group in CapabilityGroup.values) {
          final label = AdminText.group(strings, group);
          expect(label.trim(), isNotEmpty, reason: group.name);
        }
      });

      test('every risk level has a name', () {
        for (final level in PermissionRisk.values) {
          expect(AdminText.risk(strings, level).trim(), isNotEmpty);
        }
      });
    });
  }

  test('every capability appears in exactly one group', () {
    // The Roles pane renders group by group, so a capability in none of them is
    // a permission nobody can grant — and one in two is a checkbox that
    // disagrees with itself.
    final counts = <String, int>{};
    for (final group in CapabilityGroup.values) {
      for (final capability in group.capabilities) {
        counts[capability] = (counts[capability] ?? 0) + 1;
      }
    }

    expect(
      [for (final c in PosCapability.all) if (!counts.containsKey(c)) c],
      isEmpty,
      reason: 'in no group, so ungrantable from the Roles pane',
    );
    expect(
      [for (final entry in counts.entries) if (entry.value > 1) entry.key],
      isEmpty,
      reason: 'in more than one group',
    );
    expect(
      [for (final c in counts.keys) if (!PosCapability.all.contains(c)) c],
      isEmpty,
      reason: 'grouped but not a capability — a typo, or a removed one',
    );
  });

  test('every capability has a risk level', () {
    // The badge is how an owner tells "See reports" from "Restore the
    // database". A capability with no level would badge as the mildest.
    for (final capability in PosCapability.all) {
      expect(
        PosCapability.isClassified(capability),
        isTrue,
        reason: capability,
      );
    }
  });
}
