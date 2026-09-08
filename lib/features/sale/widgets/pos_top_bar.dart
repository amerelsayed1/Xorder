import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../admin/presentation/manage_menu.dart';
import '../../cash/presentation/cash_dialogs.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/repositories/repositories.dart';
import '../../admin/presentation/management_screen.dart' show ManagementPane;

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
    required this.onManage,
    this.supportedOrderTypes = OrderType.values,
  });

  final PosSession session;
  final VoidCallback onLock;
  final VoidCallback onCloseShift;

  /// Where a back-office pane was asked for. The bar does not know the routes.
  final void Function(ManagementPane pane) onManage;

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
            // Which pill depends on which question this terminal has.
            //
            // A cloud till owes its sales to the platform, so it shows what is
            // owed and the pill *is* the manual sync control — one tap runs a
            // real pass. An offline till owes them to nobody: it showed
            // "offline · 0 queued" permanently, which announces a correct and
            // intended state as though it were a fault, beside a counter that
            // can only ever read zero. What it shows instead is the branch
            // server, because that is the thing that can actually stop it
            // selling.
            if (ref.watch(cloudSyncProvider) case final cloud?)
              SyncPill(
                online: ui.online,
                queued: sync.valueOrNull,
                hasError: sync.hasError,
                onTap: () {
                  cloud.kick();
                  posToast(context, strings.syncingWithPlatform);
                },
              )
            else
              Builder(
                builder: (context) {
                  final branch = ref.watch(branchDatabaseProvider);
                  return BranchServerPill(
                    checking: branch.isLoading,
                    // A failure to *probe* is itself unreachable — the probe
                    // returning a failure and the probe throwing mean the same
                    // thing to a cashier.
                    reachable: branch.hasValue && branch.value == null,
                    onTap: () => ref.invalidate(branchDatabaseProvider),
                  );
                },
              ),
            const SizedBox(width: PosSpace.s14),
            PosButton(
              label: strings.openDrawer,
              height: 38,
              foreground: context.pos.shellText,
              border: Border.fromBorderSide(context.pos.shellBorder),
              // The real §23 act: permission, confirmation, audit row. This
              // button toasted "drawer opened" and opened nothing — the F10
              // binding was wired to the flow and this was left behind, which
              // is the more visible of the two.
              onPressed: () async {
                final opened = await DrawerOpenFlow.run(context, ref);
                if (opened && context.mounted) {
                  posToast(context, context.strings.drawerOpened);
                }
              },
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
            // **The back office, from where somebody actually asks for it.**
            // Nine panes had one door and it was on the start screen, so
            // "where do I enter this invoice" meant leaving the sale screen,
            // landing on Staff and reading a rail. This lists every pane the
            // signed-in person has and goes straight there — and renders
            // nothing at all for a cashier, because a greyed-out Manage button
            // is a permanent advertisement for a door they never get.
            ManageMenu(
              onPick: (pane) => onManage(pane),
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
