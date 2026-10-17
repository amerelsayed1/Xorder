import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../cash/presentation/cash_dialogs.dart';
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
            // The open shift, not the session. `PosSession.shiftReference` is
            // empty against a real database — shifts are their own record now,
            // and the till shows the one it actually has open.
            _shiftLabel(
              strings,
              ref.watch(shiftProvider).valueOrNull,
              pos: context.pos,
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
            // Whoever entered a PIN, and NOTHING before one has been entered.
            // This used to read `session.userName`, which the branch server
            // answers with the first active staff row rather than with the
            // person holding the till — see `operatorNameProvider`.
            if (ref.watch(operatorNameProvider) case final operator
                when operator.isNotEmpty) ...[
              const SizedBox(width: PosSpace.s14),
              _avatar(pos: context.pos, initials: ref.watch(operatorInitialsProvider)),
              const SizedBox(width: PosSpace.sm),
              Text(
                operator,
                style: PosText.ui(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: context.pos.shellText,
                ),
              ),
            ],
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
            color: pos.onAccent,
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

  /// "SHIFT #0001" — or "الوردية #0001" — or the no-shift notice.
  ///
  /// The word is the language's and the number is the till's: `shiftLabel`
  /// puts them in one string, and this draws the digits in mono whatever face
  /// the word takes, because every figure on the till is mono and a shift
  /// number read out to a manager over the phone is a figure. The mono face
  /// has no Arabic, so the Arabic word goes in the UI face rather than in
  /// whatever the platform substitutes.
  Widget _shiftLabel(
    AppStrings strings,
    PosShift? shift, {
    required PosPalette pos,
  }) {
    final digits = PosText.mono(size: 11.5, color: pos.shellMuted);
    if (shift == null) {
      return Text(strings.noShift, style: _wordStyle(strings.noShift, pos));
    }
    final label = strings.shiftLabel(shift.number);
    final at = label.indexOf(shift.number);
    if (at < 0) return Text(label, style: _wordStyle(label, pos));
    final before = label.substring(0, at);
    final after = label.substring(at + shift.number.length);
    return Text.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty)
            TextSpan(text: before, style: _wordStyle(before, pos)),
          TextSpan(text: shift.number, style: digits),
          if (after.isNotEmpty)
            TextSpan(text: after, style: _wordStyle(after, pos)),
        ],
      ),
    );
  }

  static final _arabic = RegExp(r'[\u0600-\u06FF]');

  TextStyle _wordStyle(String text, PosPalette pos) => _arabic.hasMatch(text)
      ? PosText.ui(size: 11.5, weight: FontWeight.w600, color: pos.shellMuted)
      : PosText.mono(size: 11.5, color: pos.shellMuted);

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

  Widget _avatar({required PosPalette pos, required String initials}) =>
      Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    color: pos.shellCard,
    child: Text(
      initials,
      style: PosText.ui(
        size: 11.5,
        weight: FontWeight.w800,
        color: pos.accent,
      ),
    ),
  );
}
