import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/ticket.dart';

/// The tickets this till has put down with no table, and the way back to one.
///
/// A list rather than a screen: picking one up is a two-second act in the middle
/// of service, and a route would take the cashier off the till and back again
/// for it. It is also deliberately **not** the floor screen — see the comment on
/// the counter in `CartPanel._header` for why a held ticket must not be given a
/// tile among the tables.
///
/// Read-only apart from the resume. A held ticket cannot be voided from here on
/// purpose: voiding is a permission, a reason and an audit row (`OrderVoidFlow`),
/// and a list is the wrong place to start something that asks three questions.
/// Bring the ticket back and void it where every other ticket is voided.
class HeldTicketsDialog extends StatelessWidget {
  const HeldTicketsDialog({super.key, required this.tickets});

  final List<Ticket> tickets;

  /// Returns the ticket to resume, or null if the cashier changed their mind.
  static Future<Ticket?> show(
    BuildContext context, {
    required List<Ticket> tickets,
  }) => showDialog<Ticket>(
    context: context,
    builder: (_) => HeldTicketsDialog(tickets: tickets),
  );

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogReason),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Padding(
            padding: const EdgeInsets.all(PosSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.heldTickets,
                  style: PosText.ui(
                    size: 18,
                    weight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: PosSpace.xs),
                Text(
                  strings.heldTicketsHelp,
                  style: PosText.ui(size: 12.5, color: palette.muted),
                ),
                const SizedBox(height: PosSpace.md),
                if (tickets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: PosSpace.md,
                    ),
                    child: Text(
                      strings.noHeldTickets,
                      style: PosText.ui(size: 13.5, color: palette.muted),
                    ),
                  )
                else
                  // Bounded, and scrolls past it. A till that has held eleven
                  // tickets is a till having a bad afternoon, and the dialog
                  // must not grow taller than the window it opens in.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: tickets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 1),
                      itemBuilder: (_, index) => _HeldRow(
                        ticket: tickets[index],
                        onTap: () =>
                            Navigator.of(context).pop(tickets[index]),
                      ),
                    ),
                  ),
                const SizedBox(height: PosSpace.md),
                PosButton(
                  label: strings.cancel,
                  border: Border.fromBorderSide(palette.resting),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One held ticket: what kind of order it is, how much food is on it, and what
/// it comes to. Enough for a cashier to recognise the customer standing there.
class _HeldRow extends StatelessWidget {
  const _HeldRow({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final items = ticket.lines.fold(0, (sum, line) => sum + line.quantity);

    return Material(
      color: palette.page,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PosSpace.md,
            vertical: PosSpace.md,
          ),
          decoration: BoxDecoration(border: Border.fromBorderSide(palette.resting)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.heldTicketSummary(
                    ticket.orderType.label(strings),
                    items,
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
              const SizedBox(width: PosSpace.sm),
              MonoAmount(ticket.totals.total, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
