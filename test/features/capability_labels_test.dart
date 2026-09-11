import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';
import 'package:xorder_pos/domain/models/supplier_invoice.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';

/// Every key this build shows a person is a sentence, not a wire value.
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

      test('every audit action this build writes has a sentence', () {
        // **The Activity pane rendered `entry.action` raw.** Every row read
        // `supplier_invoice.saved`, in both languages, on the screen a
        // restaurant looks at to find out who changed something — and unlike
        // the unlabelled capability there was no switch with a missing case,
        // there was no switch.
        final unlabelled = [
          for (final action in _actionsThisBuildWrites)
            if (AdminText.auditAction(strings, action) == action) action,
        ];

        expect(
          unlabelled,
          isEmpty,
          reason:
              'These render as raw keys in the Activity pane. Add a case to '
              'AdminText.auditAction and a string in both languages.',
        );
      });

      test('every unit is a word somebody writes on a delivery note', () {
        // `ea` is not one, least of all in Arabic, where it means nothing.
        for (final unit in QuantityUnit.values) {
          final label = AdminText.unit(strings, unit);
          expect(label.trim(), isNotEmpty, reason: unit.wire);
          expect(
            label,
            isNot('ea'),
            reason: 'the wire token leaked through for ${unit.wire}',
          );
        }
      });

      test('every purchase status and payment method is named', () {
        // Only non-empty, deliberately. Both are keyed by the **enum** rather
        // than by a wire string, so a new member fails to compile instead of
        // falling through — there is no silent path left to catch. And the
        // wire-inequality check the capability test uses would be wrong here:
        // the English word for the `draft` status is, correctly, "draft".
        for (final status in PurchaseStatus.values) {
          expect(
            AdminText.purchaseStatus(strings, status).trim(),
            isNotEmpty,
            reason: status.name,
          );
        }
        for (final method in SupplierPaymentMethod.values) {
          expect(
            AdminText.paymentMethod(strings, method).trim(),
            isNotEmpty,
            reason: method.name,
          );
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

  test('the list of audit actions below is the whole list', () {
    // **The hand-written list is the weak point**, so it is checked against the
    // source rather than trusted. Every `AuditAction` constant whose value
    // contains a dot is an action (the entity types have none), which makes the
    // real set greppable — the same trick `grants_cover_usage_test.dart` uses,
    // for the same reason: a list nobody re-reads is the failure mode this file
    // exists to catch.
    final source = File(
      '${Directory.current.path}/lib/domain/repositories/admin_repositories.dart',
    ).readAsStringSync();

    final declared = RegExp(r"static const \w+ = '([a-z_]+\.[a-z_]+)';")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      declared.difference(_actionsThisBuildWrites.toSet()),
      isEmpty,
      reason:
          'These audit actions exist and are not in the list below, so nothing '
          'checks that they have a label. Add them.',
    );
    expect(
      _actionsThisBuildWrites.toSet().difference(declared),
      isEmpty,
      reason: 'listed below and no longer declared — a rename, or a removal',
    );
    expect(
      _actionsThisBuildWrites.length,
      _actionsThisBuildWrites.toSet().length,
      reason: 'listed twice',
    );
  });
}

/// Every action constant on [AuditAction], listed by hand.
///
/// Dart cannot reflect over a class of constants, so this is written out — and
/// checked against the source above, so that adding an action without adding it
/// here fails.
const _actionsThisBuildWrites = <String>[
  AuditAction.staffCreated,
  AuditAction.staffUpdated,
  AuditAction.staffDisabled,
  AuditAction.staffReactivated,
  AuditAction.staffPinReset,
  AuditAction.staffRoleChanged,
  AuditAction.staffGrantsChanged,
  AuditAction.roleCreated,
  AuditAction.roleUpdated,
  AuditAction.roleDeleted,
  AuditAction.permissionOverridden,
  AuditAction.shiftOpened,
  AuditAction.shiftClosed,
  AuditAction.receiptReprinted,
  AuditAction.categoryCreated,
  AuditAction.categoryUpdated,
  AuditAction.categoryArchived,
  AuditAction.categoryRestored,
  AuditAction.productCreated,
  AuditAction.productUpdated,
  AuditAction.productArchived,
  AuditAction.productRestored,
  AuditAction.productRepriced,
  AuditAction.moneyConfigChanged,
  AuditAction.receiptProfileChanged,
  AuditAction.tableCreated,
  AuditAction.tableUpdated,
  AuditAction.tableArchived,
  AuditAction.tableRestored,
  AuditAction.purchaseOrderStatusChanged,
  AuditAction.stockReceived,
  AuditAction.supplierSaved,
  AuditAction.supplierInvoiceSaved,
  AuditAction.supplierInvoiceVoided,
  AuditAction.supplierPaid,
  AuditAction.supplierPaymentVoided,
  AuditAction.serviceChargeSaved,
  AuditAction.unitSaved,
  AuditAction.stockItemSaved,
  AuditAction.tenderTypeSaved,
  AuditAction.orderTypeSaved,
  AuditAction.taxGroupSaved,
  AuditAction.backupTaken,
  AuditAction.backupRestored,
];
