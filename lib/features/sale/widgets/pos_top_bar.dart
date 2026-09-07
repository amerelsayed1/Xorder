import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
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
    final sync = ref.watch(pendingSyncCountProvider);

    final strings = context.strings;

    return Container(
      height: PosSize.topBar,
      decoration: BoxDecoration(
        color: context.pos.shell,
        border: Border(bottom: context.pos.accentBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
        child: Row(
          children: [
            _identity(pos: context.pos),
            const SizedBox(width: PosSpace.s24),
            _modeSwitch(ref, ticket.orderType, strings, pos: context.pos),
            const SizedBox(width: PosSpace.s24),
            SyncPill(
              online: ui.online,
              queued: sync.valueOrNull,
              hasError: sync.hasError,
              // On a cloud terminal the pill *is* the manual sync control —
              // one tap runs a real pass (heartbeat, config check, drain).
              // That is what makes SyncPolicy.manual honest: the operator
              // chooses when money moves, from the thing that shows what is
              // owed. Elsewhere it keeps the prototype online toggle.
              onTap: () {
                final cloud = ref.read(cloudSyncProvider);
                if (cloud == null) {
                  ref.read(posUiProvider.notifier).toggleOnline();
                  return;
                }
                cloud.kick();
                posToast(context, strings.syncingWithPlatform);
              },
            ),
            const SizedBox(width: PosSpace.s14),
            PosButton(
              label: strings.openDrawer,
              height: 38,
              foreground: context.pos.shellText,
              border: Border.fromBorderSide(context.pos.shellBorder),
              onPressed: () => posToast(context, strings.drawerOpenedToast),
            ),
            const SizedBox(width: PosSpace.s14),
            Text(
              // The open shift, not the session. `PosSession.shiftReference` is
              // empty against a real database — shifts are their own record now,
              // and the till shows the one it actually has open.
              ref.watch(shiftProvider).valueOrNull?.reference ??
                  strings.noShift,
              style: PosText.mono(size: 11.5, color: context.pos.shellMuted),
            ),
            const SizedBox(width: PosSpace.s14),
            PosButton(
              label: strings.lock,
              height: 38,
              foreground: context.pos.shellText,
              border: Border.fromBorderSide(context.pos.shellBorder),
              onPressed: onLock,
            ),
            const SizedBox(width: PosSpace.s14),
            PosButton(
              label: strings.closeShift,
              height: 38,
              foreground: context.pos.offlinePillText,
              border: Border.all(color: context.pos.warn),
              onPressed: onCloseShift,
            ),
            const SizedBox(width: PosSpace.s14),
            _avatar(pos: context.pos),
            const SizedBox(width: PosSpace.sm),
            Text(
              session.userName,
              style: PosText.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: context.pos.shellText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identity({required PosPalette pos}) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        color: pos.accent,
        child: Text(
          session.tenantName.characters.first.toUpperCase(),
          style: PosText.ui(
            size: 16,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      const SizedBox(width: PosSpace.s10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            session.tenantName,
            style: PosText.ui(
              size: 13.5,
              weight: FontWeight.w600,
              color: pos.shellText,
            ),
          ),
          Text(
            '${session.branchName} · ${session.terminalCode}',
            style: PosText.mono(size: 10.5, color: pos.shellMuted),
          ),
        ],
      ),
    ],
  );

  /// Segmented control inside a 1px shellLine box — no gaps, no radius.
  Widget _modeSwitch(
    WidgetRef ref,
    OrderType active,
    AppStrings strings,{required PosPalette pos}
  ) => Container(
    decoration: BoxDecoration(
      border: Border.fromBorderSide(pos.shellBorder),
    ),
    child: Row(
      children: [
        for (final type in supportedOrderTypes)
          Material(
            color: type == active ? pos.accent : Colors.transparent,
            child: InkWell(
              onTap: () => ref.read(ticketProvider.notifier).setOrderType(type),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
                alignment: Alignment.center,
                child: Text(
                  type.label(strings),
                  style: PosText.ui(
                    size: 13,
                    weight: type == active ? FontWeight.w600 : FontWeight.w500,
                    color: type == active ? Colors.white : pos.shellText,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _avatar({required PosPalette pos}) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    color: pos.shellCard,
    child: Text(
      session.initials,
      style: PosText.ui(
        size: 11.5,
        weight: FontWeight.w800,
        color: pos.accent,
      ),
    ),
  );
}
