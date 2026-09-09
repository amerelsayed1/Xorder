import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import 'management_screen.dart';

/// One tap to any back-office pane.
///
/// **Nine panes had one door.** Management opened on Staff and everything else
/// was found by reading a rail — which is fine once somebody is inside it and
/// useless from the till, where the question is *"where do I enter an
/// invoice"*. So this lists every pane the person actually has, with the same
/// sentence the rail shows, and goes straight there.
///
/// It asks [managementPanesFor], rather than listing panes itself, for the
/// reason that function exists: a menu offering Purchasing to somebody the rail
/// hides it from would take them to a screen that refuses everything.
///
/// **Not a hover menu.** A till is a touch surface first, and the theme turns
/// every hover tint off on purpose — a menu that only opened on hover would be
/// a menu that never opened. Tapping opens it; the tooltip on the button is
/// there for the desktop case, where a pointer exists.
class ManageMenu extends ConsumerWidget {
  const ManageMenu({
    super.key,
    required this.onPick,
    this.label,
    this.height = 38,
    this.onShell = false,
  });

  /// Where the caller sends them. The route, not the pane — this widget knows
  /// nothing about `go_router`.
  final void Function(ManagementPane pane) onPick;

  final String? label;
  final double height;

  /// Whether it sits on the dark shell (the till's top bar) or on page ground
  /// (the start screen). Only the colours differ.
  final bool onShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final palette = context.pos;
    final admin = ref.watch(signedInStaffProvider);

    // Nothing to offer somebody who cannot open the back office at all. Absent
    // rather than disabled: a greyed-out Manage button on a cashier's till is a
    // permanent advertisement for a door they will never be given.
    if (admin == null || !admin.can(PosCapability.staffManage)) {
      return const SizedBox.shrink();
    }

    final areas = managementAreasFor(
      admin: admin,
      authorsItsOwnCatalogue: ref.watch(catalogAdminRepositoryProvider) != null,
    );
    if (areas.isEmpty) return const SizedBox.shrink();

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surface),
        // Flat and square, like everything else. Material's default here is a
        // rounded card with an elevation shadow.
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(side: palette.emphasis),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        maximumSize: const WidgetStatePropertyAll(Size(320, 620)),
      ),
      menuChildren: [
        // Grouped exactly as the rail groups them, and for the same reason:
        // "where do I change the VAT rate" is answered by *Money* long before
        // it is answered by reading eleven pane names.
        for (final (area, panes) in areas) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: PosSpace.md,
              right: PosSpace.md,
              top: PosSpace.sm,
              bottom: 2,
            ),
            child: MicroLabel(managementAreaName(strings, area)),
          ),
          for (final pane in panes)
            _MenuRow(
              key: Key('manage-menu-${pane.name}'),
              pane: pane,
              onPressed: () => onPick(pane),
            ),
        ],
      ],
      builder: (context, controller, _) => Tooltip(
        message: strings.manageMenuTooltip,
        child: PosButton(
          key: const Key('manage-menu'),
          label: label ?? strings.manage,
          height: height,
          foreground: onShell ? palette.shellText : null,
          border: Border.fromBorderSide(
            onShell ? palette.shellBorder : palette.resting,
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}

/// One pane, named and explained.
///
/// The blurb is not decoration: "Purchasing" and "Receipt" are guesses until
/// somebody reads what they do, and the whole point of this menu is not having
/// to open three panes to find one.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.pane, required this.onPressed, super.key});

  final ManagementPane pane;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final (title, hint) = managementPaneLabel(context.strings, pane);

    return MenuItemButton(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: PosSpace.md, vertical: PosSpace.sm),
        ),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        overlayColor: WidgetStatePropertyAll(palette.chipBg),
      ),
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: PosText.ui(
                size: 13.5,
                weight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              hint,
              style: PosText.ui(size: 11, color: palette.muted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
