import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/widgets/destructive_confirm_dialog.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/repositories/repositories.dart'
    show CheckChangedElsewhere;
import '../../../domain/services/authorization.dart';
import '../../../domain/services/ticket_engine.dart';
import '../../admin/presentation/supervisor_override.dart';

/// Taking a line off the ticket — and which of the two acts that is.
///
/// **The distinction is the feature.** Removing something the kitchen has not
/// seen is housekeeping: a cashier fixing a mis-tap, nothing made, nothing
/// wasted, and a confirmation heavy enough to make them think twice would just
/// be in the way. Once the line has been fired it is waste with a cost, and it
/// gets the full destructive treatment: consequences spelled out, a reason
/// required, a supervisor if the cashier does not hold the permission, and the
/// line left on the ticket afterwards so the customer can be shown what
/// happened.
///
/// One entry point rather than two, because the caller should not have to
/// classify the act — the line's own stage already does.
abstract final class LineVoidFlow {
  /// Returns the changed ticket, or null if nothing happened.
  static Future<Ticket?> run(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
    required String lineKey,
  }) async {
    final line = ticket.lines.where((l) => l.key == lineKey).firstOrNull;
    if (line == null) return null;

    return line.stage == LineStage.draft
        ? _cancel(context, ref, ticket: ticket, line: line)
        : _void(context, ref, ticket: ticket, line: line);
  }

  /// Nothing has been made. Confirm lightly, record quietly, move on.
  static Future<Ticket?> _cancel(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
    required TicketLine line,
  }) async {
    final strings = context.strings;
    final staff = ref.read(signedInStaffProvider);

    final decision = Authorization.check(staff, PosCapability.orderItemCancel);
    if (decision is! Allowed) {
      // Not overridable — see `PosCapability.overridable`. A restaurant that
      // has taken this off a role has decided cashiers do not edit tickets,
      // and a supervisor prompt would quietly undo that decision.
      await requestPermission(
        context,
        ref,
        PosCapability.orderItemCancel,
        action: strings.cancelLineAction,
        auditAction: 'order.item.cancel',
        entityId: ticket.id,
      );
      return null;
    }

    if (!context.mounted) return null;
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: strings.cancelLineTitle(
        line.product.displayName(strings.languageCode),
      ),
      confirmLabel: strings.cancelLineAction,
      keepLabel: strings.keepLineAction,
      amount: line.lineTotal,
      consequences: [strings.cancelLineNothingMade],
      // **No reason asked for.** The SRS requires one for a void; a cashier
      // correcting their own mis-tap before anything was cooked is not an act
      // anybody reviews, and demanding a justification for it teaches people to
      // pick the first item in the list.
      requirement: ReasonRequirement.disabled,
    );
    if (confirmed == null) return null;

    return TicketEngine.cancelLine(
      ticket,
      line.key,
      by: staff?.id ?? 0,
      now: DateTime.now(),
    ).ticket;
  }

  /// The kitchen already made it. Full weight.
  static Future<Ticket?> _void(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
    required TicketLine line,
  }) async {
    final strings = context.strings;
    final staff = ref.read(signedInStaffProvider);
    final item = line.product.displayName(strings.languageCode);

    // Whether this person may void a cooked line at all. Overridable, so a
    // cashier reaches it through a supervisor standing at the till.
    final decision = Authorization.check(staff, PosCapability.orderItemVoid);

    // Loaded before either branch touches the context, so there is no async gap
    // between checking `mounted` and showing a dialog.
    final reasons = await ref.read(
      reasonCodesProvider(ReasonScope.voidAct).future,
    );
    if (!context.mounted) return null;

    int? approvedById;
    String? approvedByName;

    if (decision is! Allowed) {
      final lent = await requestPermission(
        context,
        ref,
        PosCapability.orderItemVoid,
        action: strings.voidLineTitle(item),
        auditAction: 'order.item.void',
        entityId: ticket.id,
        requestedBy: staff?.name,
        subject: '${line.quantity} × $item · ${line.lineTotal.format(withCurrency: true)}',
        approveLabel: strings.voidLineAction,
        reasons: reasons,
        reasonRequirement: SystemReasons.defaultRequirement(
          ReasonScope.voidAct,
        ),
      );
      if (lent is! Allowed || lent.approvedBy == null) return null;
      approvedById = lent.approvedBy!.id;
      approvedByName = lent.approvedBy!.name;

      // The supervisor already gave a reason when they approved. Asking the
      // cashier for a second one would be the same question twice, with a
      // customer waiting.
      if (!context.mounted) return null;
      return TicketEngine.voidLine(
        ticket,
        line.key,
        by: staff?.id ?? approvedById,
        now: DateTime.now(),
        reasonId: lent.reason?.reasonId,
        note: lent.reason?.note,
        approvedByStaffId: approvedById,
        approvedByName: approvedByName,
      ).ticket;
    }

    if (!context.mounted) return null;
    final outcome = await DestructiveConfirmDialog.show(
      context,
      title: strings.voidLineTitle(item),
      confirmLabel: '${strings.voidLineAction} · ${line.lineTotal.format(withCurrency: true)}',
      keepLabel: strings.keepLineAction,
      amount: line.lineTotal,
      // Three, in the handoff's order: what happens · what it does to work
      // already done · what cannot be undone.
      consequences: [
        strings.voidLineConsequenceRemoved(line.lineTotal.format(withCurrency: true)),
        strings.voidLineConsequenceKitchen,
        strings.voidLineConsequenceIrreversible,
      ],
      reasons: reasons,
      requirement: SystemReasons.defaultRequirement(ReasonScope.voidAct),
    );
    if (outcome == null) return null;

    return TicketEngine.voidLine(
      ticket,
      line.key,
      by: staff?.id ?? 0,
      now: DateTime.now(),
      reasonId: outcome.reasonId,
      note: outcome.note,
    ).ticket;
  }
}

/// Voiding the whole ticket.
///
/// **The boundary is whether the kitchen has seen any of it.** A ticket with
/// nothing sent is somebody's abandoned keystrokes: clearing it is not a
/// business event and writing a row for it would fill the ledger with noise. As
/// soon as one round has been fired the opposite holds — food was made, the
/// cost is real, and a restaurant that cannot total its waste cannot manage it.
///
/// So the two paths differ in what they *record*, not only in how loudly they
/// ask.
abstract final class OrderVoidFlow {
  /// Returns true when the ticket should be discarded by the caller.
  ///
  /// The void itself is already written by then — the caller's job is only to
  /// clear the screen and release the table.
  static Future<OrderVoidOutcome?> run(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
  }) async {
    if (ticket.isEmpty) return const OrderVoidOutcome.discard();

    final anySent = ticket.lines.any(
      (l) => l.stage == LineStage.sent && !l.isVoided,
    );
    return anySent
        ? _void(context, ref, ticket: ticket)
        : _clear(context, ref, ticket: ticket);
  }

  /// Nothing was fired. Confirm, then throw it away, and record nothing.
  static Future<OrderVoidOutcome?> _clear(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
  }) async {
    final strings = context.strings;

    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: strings.clearTicketTitle,
      confirmLabel: strings.voidTicket,
      keepLabel: strings.keepOrderAction,
      amount: ticket.totals.total,
      consequences: [strings.clearTicketNothingSent],
      // No reason: there is nothing to explain to anybody, because there will
      // be no record for anybody to read.
      requirement: ReasonRequirement.disabled,
    );

    return confirmed == null ? null : const OrderVoidOutcome.discard();
  }

  /// The kitchen made some of it. Ask properly, then write it down.
  static Future<OrderVoidOutcome?> _void(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
  }) async {
    final strings = context.strings;
    final staff = ref.read(signedInStaffProvider);
    final reference = ticket.tableLabel ?? strings.voidOrderAction;

    final reasons = await ref.read(
      reasonCodesProvider(ReasonScope.voidAct).future,
    );
    if (!context.mounted) return null;

    final decision = Authorization.check(staff, PosCapability.orderVoid);

    if (decision is! Allowed) {
      final lent = await requestPermission(
        context,
        ref,
        PosCapability.orderVoid,
        action: strings.voidOrderTitle(reference),
        auditAction: 'order.void',
        entityId: ticket.id,
        requestedBy: staff?.name,
        subject: ticket.totals.total.format(withCurrency: true),
        approveLabel: strings.voidOrderAction,
        reasons: reasons,
        reasonRequirement: SystemReasons.defaultRequirement(
          ReasonScope.voidAct,
        ),
      );
      if (lent is! Allowed || lent.approvedBy == null) return null;

      if (!context.mounted) return null;
      return _write(
        context,
        ref,
        ticket: ticket,
        by: staff ?? lent.approvedBy!,
        reasonId: lent.reason?.reasonId,
        note: lent.reason?.note,
        // The approval, which the repository spends on this ticket and no
        // other — not only the supervisor's name.
        approval: lent.approval,
      );
    }

    if (!context.mounted) return null;
    final outcome = await DestructiveConfirmDialog.show(
      context,
      title: strings.voidOrderTitle(reference),
      confirmLabel:
          '${strings.voidOrderAction} · ${ticket.totals.total.format(withCurrency: true)}',
      keepLabel: strings.keepOrderAction,
      amount: ticket.totals.total,
      consequences: [
        strings.voidOrderConsequenceBill(ticket.totals.total.format(withCurrency: true)),
        strings.voidOrderConsequenceKitchen,
        strings.voidOrderConsequenceRecorded,
      ],
      reasons: reasons,
      requirement: SystemReasons.defaultRequirement(ReasonScope.voidAct),
    );
    if (outcome == null || staff == null) return null;
    if (!context.mounted) return null;

    return _write(
      context,
      ref,
      ticket: ticket,
      by: staff,
      reasonId: outcome.reasonId,
      note: outcome.note,
    );
  }

  /// Write it, and say what it was recorded as.
  ///
  /// A failure here is **not** swallowed into a cleared screen. The whole point
  /// of the heavy path is that the waste ends up on the ledger; a void that
  /// silently failed and cleared the ticket anyway would lose both the food and
  /// the record of it.
  static Future<OrderVoidOutcome?> _write(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
    required PosStaff by,
    int? reasonId,
    String? note,
    Approval? approval,
  }) async {
    try {
      final result = await ref
          .read(ordersRepositoryProvider)
          .voidOrder(
            ticket,
            by: by,
            reasonId: reasonId,
            note: note,
            approval: approval,
            // As at payment: an outdated copy of a check is not voided.
            parkedVersion: ref
                .read(openTicketsProvider.notifier)
                .versionOf(ticket),
          );
      return OrderVoidOutcome.recorded(result.invoiceNumber);
    } on CheckChangedElsewhere {
      return const OrderVoidOutcome.changedElsewhere();
    } on Object catch (error) {
      return OrderVoidOutcome.failed('$error');
    }
  }
}

/// What the caller should do next.
class OrderVoidOutcome {
  const OrderVoidOutcome.discard()
    : invoiceNumber = null,
      error = null,
      changedElsewhere = false,
      shouldDiscard = true;

  const OrderVoidOutcome.recorded(this.invoiceNumber)
    : error = null,
      changedElsewhere = false,
      shouldDiscard = true;

  /// The write failed. **The ticket is kept**, so the food and the record of it
  /// are not both lost.
  const OrderVoidOutcome.failed(this.error)
    : invoiceNumber = null,
      changedElsewhere = false,
      shouldDiscard = false;

  /// Refused because another till changed this check since (XORD-046
  /// follow-up). Nothing was recorded and the ticket is kept.
  const OrderVoidOutcome.changedElsewhere()
    : invoiceNumber = null,
      error = null,
      changedElsewhere = true,
      shouldDiscard = false;

  final String? invoiceNumber;
  final String? error;
  final bool changedElsewhere;
  final bool shouldDiscard;
}
