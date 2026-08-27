import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/repositories/repositories.dart';

/// 56px top bar on shell ground with a 2px accent bottom border.
///
/// Horizontally scrollable with every child at intrinsic width, because the
/// handoff is explicit that no label may ever be clipped.
class PosTopBar extends ConsumerWidget {
  const PosTopBar({
    super.key,
    required this.session,
    required this.onLock,
    required this.onCloseShift,
    this.supportedOrderTypes = OrderType.values,
  });

  final PosSession session;
  final VoidCallback onLock;
  final VoidCallback onCloseShift;

  /// Comes from `branch.supported_order_types` (POS-BE-005). Only enabled types
  /// are shown — never a hardcoded set, and never a visibly disabled control.
  final List<OrderType> supportedOrderTypes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(posUiProvider);
    final ticket = ref.watch(ticketProvider);

    return Container(
      height: PosSize.topBar,
      decoration: const BoxDecoration(
        color: PosColors.shell,
        border: Border(bottom: PosBorders.accent),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
        child: Row(
          children: [
            _identity(),
            const SizedBox(width: PosSpace.s24),
            _modeSwitch(ref, ticket.orderType),
            const SizedBox(width: PosSpace.s24),
            SyncPill(
              online: ui.online,
              queued: ui.queuedCount,
              onTap: () => ref.read(posUiProvider.notifier).toggleOnline(),
            ),
            const SizedBox(width: PosSpace.s14),
            PosButton(
              label: 'Open drawer',
              height: 38,
              foreground: PosColors.shellText,
              border: const Border.fromBorderSide(PosBorders.shell),
              onPressed: () => posToast(context, 'Cash drawer opened · F10'),
            ),
            const SizedBox(width: PosSpace.s14),
            Text(
              // The open shift, not the session. `PosSession.shiftReference` is
              // empty against a real database — shifts are their own record now,
              // and the till shows the one it actually has open.
              ref.watch(shiftProvider).valueOrNull?.reference ?? 'NO SHIFT',
              style: PosText.mono(size: 11.5, color: PosColors.shellMuted),
            ),
            const SizedBox(width: PosSpace.s14),
            PosButton(
              label: 'Lock',
              height: 38,
              foreground: PosColors.shellText,
              border: const Border.fromBorderSide(PosBorders.shell),
              onPressed: onLock,
            ),
            const SizedBox(width: PosSpace.s14),
            PosButton(
              label: 'Close shift',
              height: 38,
              foreground: PosColors.offlinePillText,
              border: Border.all(color: PosColors.warn),
              onPressed: onCloseShift,
            ),
            const SizedBox(width: PosSpace.s14),
            _avatar(),
            const SizedBox(width: PosSpace.sm),
            Text(
              session.userName,
              style: PosText.ui(size: 13.5, weight: FontWeight.w600, color: PosColors.shellText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identity() => Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            color: PosColors.accent,
            child: Text(
              session.tenantName.characters.first.toUpperCase(),
              style: PosText.ui(size: 16, weight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(width: PosSpace.s10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                session.tenantName,
                style: PosText.ui(size: 13.5, weight: FontWeight.w600, color: PosColors.shellText),
              ),
              Text(
                '${session.branchName} · ${session.terminalCode}',
                style: PosText.mono(size: 10.5, color: PosColors.shellMuted),
              ),
            ],
          ),
        ],
      );

  /// Segmented control inside a 1px shellLine box — no gaps, no radius.
  Widget _modeSwitch(WidgetRef ref, OrderType active) => Container(
        decoration: const BoxDecoration(border: Border.fromBorderSide(PosBorders.shell)),
        child: Row(
          children: [
            for (final type in supportedOrderTypes)
              Material(
                color: type == active ? PosColors.accent : Colors.transparent,
                child: InkWell(
                  onTap: () => ref.read(ticketProvider.notifier).setOrderType(type),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
                    alignment: Alignment.center,
                    child: Text(
                      type.label,
                      style: PosText.ui(
                        size: 13,
                        weight: type == active ? FontWeight.w600 : FontWeight.w500,
                        color: type == active ? Colors.white : PosColors.shellText,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _avatar() => Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        color: PosColors.shellCard,
        child: Text(
          session.initials,
          style: PosText.ui(size: 11.5, weight: FontWeight.w800, color: PosColors.accent),
        ),
      );
}
