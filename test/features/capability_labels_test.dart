import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/labels.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/held_sync.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/shift.dart' show ShiftStatus;
import 'package:xorder_pos/domain/models/supplier_invoice.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/application/reports_view.dart';
import 'package:xorder_pos/features/admin/application/users_overview.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';
import 'package:xorder_pos/features/admin/presentation/management_finance_panes.dart';
import 'package:xorder_pos/features/admin/presentation/management_reports_pane.dart';
import 'package:xorder_pos/features/admin/presentation/shift_history_bits.dart';

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

      test('every held sync record says what it is and why, in words', () {
        // Enum-keyed, so a missing case cannot compile; what is left to catch
        // is an empty translation, or a code pasted in where a sentence
        // belongs — `MENU_ITEM_NOT_FOUND` read out to a restaurant owner.
        for (final kind in HeldSyncKind.values) {
          expect(
            AdminText.heldSyncKind(strings, kind).trim(),
            isNotEmpty,
            reason: kind.name,
          );
        }
        final sentences = <String>{};
        for (final code in QuarantineCode.values) {
          final label = AdminText.quarantineCode(strings, code);
          expect(label.trim(), isNotEmpty, reason: code.name);
          expect(label, isNot(contains('_')), reason: code.name);
          sentences.add(label);
        }
        expect(
          sentences,
          hasLength(QuarantineCode.values.length),
          reason: 'two reasons worded alike are two problems nobody can tell '
              'apart',
        );
      });

      test('every staff status the Users filter offers is named', () {
        // Enum-keyed like the two above, so this can only catch an empty
        // translation — and three distinct words, because two filter chips
        // reading the same would be two buttons nobody can tell apart.
        final labels = [
          for (final status in StaffStatusFilter.values)
            AdminText.staffStatus(strings, status).trim(),
        ];
        expect(labels, everyElement(isNotEmpty));
        expect(labels.toSet(), hasLength(labels.length));
      });

      test("every choice on the Reports tab is named, and no two alike", () {
        // Enum-keyed, so only an empty or a repeated word is left to catch:
        // two period chips that read the same are two buttons nobody can
        // tell apart, and the same for the trend's and the ranking's.
        for (final labels in [
          [for (final p in ReportPeriod.values) reportPeriodLabel(strings, p)],
          [
            for (final m in ReportTrendMetric.values)
              reportTrendMetricLabel(strings, m),
          ],
          [
            for (final r in ProductRanking.values)
              productRankingLabel(strings, r),
          ],
        ]) {
          expect(labels.map((l) => l.trim()), everyElement(isNotEmpty));
          expect(labels.toSet(), hasLength(labels.length), reason: '$labels');
        }
      });

      test('every word Finance puts on a row, a group or a figure is named, '
          'and no two alike', () {
        // Enum-keyed like the Reports tab's (BO-10): the transactions table's
        // kinds and states, the bills-due groups, and the sentence under an
        // expenses figure for each reason the supplier ledger is or is not
        // in it. Two states reading the same would be a table that cannot
        // tell paid from recorded.
        for (final labels in [
          [
            for (final p in FinancePeriod.values)
              financePeriodLabel(strings, p),
          ],
          [
            for (final k in FinanceTransactionKind.values)
              financeKindLabel(strings, k),
          ],
          [
            for (final st in FinanceTransactionStatus.values)
              financeStatusLabel(strings, st),
          ],
          [
            for (final b in BillsDueBucket.values)
              billsDueBucketLabel(strings, b),
          ],
          [
            for (final f in SupplierFigures.values)
              supplierFiguresNote(strings, f),
          ],
        ]) {
          expect(labels.map((l) => l.trim()), everyElement(isNotEmpty));
          expect(labels.toSet(), hasLength(labels.length), reason: '$labels');
        }
      });

      test('every refund kind Returns shows is named, not its wire word, '
          'and the two differ', () {
        final labels = [
          for (final kind in RefundKind.values) refundKindLabel(strings, kind),
        ];
        expect(labels.map((l) => l.trim()), everyElement(isNotEmpty));
        for (final kind in RefundKind.values) {
          expect(refundKindLabel(strings, kind), isNot(kind.wire));
        }
        expect(labels.toSet(), hasLength(labels.length), reason: '$labels');
      });

      test('every state a shift is listed in is named, and no two alike', () {
        // People › Shifts and Finance › Settlements. Enum-keyed, so only an
        // empty or a repeated word is left to catch — and "closed" reading
        // the same as "force-closed" would hide the one close a manager is
        // looking for.
        final labels = [
          for (final status in ShiftStatus.values)
            shiftStatusLabel(strings, status).trim(),
        ];
        expect(labels, everyElement(isNotEmpty));
        expect(labels.toSet(), hasLength(labels.length), reason: '$labels');
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
  AuditAction.comboSaved,
  AuditAction.stockCostSet,
  AuditAction.productOptionsChanged,
  AuditAction.optionGroupSaved,
  AuditAction.optionGroupRepriced,
  AuditAction.optionGroupDeleted,
  AuditAction.backupTaken,
  AuditAction.backupRestored,
  AuditAction.adminEntered,
  AuditAction.adminExited,
  AuditAction.adminTimedOut,
  AuditAction.adminRefused,
  AuditAction.adminLockedOut,
  AuditAction.syncRecordReleased,
  AuditAction.lanEncryptionChanged,
];
