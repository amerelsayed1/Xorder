import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../data/postgres/pos_database.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import 'management_activity_pane.dart';
import 'management_floor_pane.dart';
import 'management_menu_pane.dart';
import 'management_eta_pane.dart';
import 'management_money_pane.dart';
import 'management_purchasing_pane.dart';
import 'management_receipt_pane.dart';
import 'management_roles_pane.dart';
import 'management_staff_pane.dart';
import '../../../core/security/pin_hash.dart';

/// The back office, inside the till.
///
/// **Reached by PIN, not by being on the right screen.** Everything else in the
/// app assumes whoever is standing there may do it — a till is a shared machine
/// and asking a cashier to sign in before every sale is how a queue forms. This
/// section is the exception: it changes what the restaurant sells, who works
/// there and what they may do, so it asks who is asking and checks before it
/// opens.
///
/// The check is repeated at every write. This gate is a door, not a guarantee:
/// the person who signs in here could hand the machine to somebody else, and
/// the repositories are what make that not matter.
class ManagementScreen extends ConsumerStatefulWidget {
  const ManagementScreen({
    required this.onClose,
    this.initialPane = ManagementPane.staff,
    super.key,
  });

  final VoidCallback onClose;

  /// Which pane to land on.
  ///
  /// Exists so a menu item can say what it opens. "Management" is a place;
  /// "Staff & accounts" is an answer to the question somebody actually has, and
  /// they should not have to learn that accounts live behind the first word to
  /// find them.
  final ManagementPane initialPane;

  @override
  ConsumerState<ManagementScreen> createState() => _ManagementScreenState();
}

/// The panes, public so a caller can name the one it means.
/// [receipt] is deliberately outside the authoring set: every terminal prints
/// a slip with the restaurant's name and address on it, cloud and offline
/// alike, and only the write side needs Management's credential.
/// Which panes this terminal and this person actually have.
///
/// **Public, and the only answer.** The rail asked this and so does the Manage
/// menu, and two lists that were meant to agree are two lists that will not —
/// a menu offering Purchasing to somebody the rail hides it from would take
/// them to a screen that refuses everything.
List<ManagementPane> managementPanesFor({
  required PosStaff admin,
  required bool authorsItsOwnCatalogue,
}) => [
  for (final pane in ManagementPane.values)
    if ((!_authoringPanes.contains(pane) || authorsItsOwnCatalogue) &&
        _permits(admin, pane))
      pane,
];

/// Menu authoring exists only where this terminal is the author of its own
/// catalogue — offline. On a cloud till the platform authors it and the
/// bootstrap seeder overwrites whatever is here, so the pane would be an
/// invitation to lose work.
///
/// **Money is not here.** Its tax rates are the platform's on a cloud till, but
/// the payment methods and service charges Wave D put in the same pane are local
/// on both deployments — so the pane gates its own top half rather than
/// disappearing, and a cloud restaurant can still say how it takes money.
const _authoringPanes = {ManagementPane.menu, ManagementPane.floor};

/// Where the caller was, and which pane they asked for.
///
/// **Both, because the way out matters as much as the way in.** The route used
/// to send every close to the start screen, which was right while the only door
/// was on the start screen. A manager who opens Purchasing from the till and
/// closes it should be back at the till with their ticket still on it, not
/// standing on a start screen wondering where the shift went.
class ManagementDestination {
  const ManagementDestination({required this.pane, this.returnTo});

  final ManagementPane pane;

  /// The route to go back to. Null means the start screen, which is what the
  /// only previous caller wanted.
  final String? returnTo;
}

/// What a pane is called, and what it is for.
///
/// A function of the language rather than a const map: this is the one place
/// that names every pane, so it is the one place a pane added without an Arabic
/// label has to fail to compile.
(String, String) managementPaneLabel(AppStrings s, ManagementPane pane) =>
    switch (pane) {
      ManagementPane.staff => (s.paneStaff, s.paneStaffBlurb),
      ManagementPane.menu => (s.paneMenu, s.paneMenuBlurb),
      ManagementPane.floor => (s.floorPlan, s.floorPlanHint),
      ManagementPane.money => (s.moneyRules, s.moneyRulesHint),
      ManagementPane.purchasing => (s.panePurchasing, s.panePurchasingBlurb),
      ManagementPane.receipt => (s.paneReceipt, s.paneReceiptBlurb),
      ManagementPane.eta => (s.paneEta, s.paneEtaBlurb),
      ManagementPane.roles => (s.paneRoles, s.paneRolesBlurb),
      ManagementPane.activity => (s.paneActivity, s.paneActivityBlurb),
    };

/// The capability a pane needs beyond the `staffManage` that opened the screen.
///
/// **Only the panes whose repositories actually enforce one appear here.**
/// Hiding a pane on a capability nothing checks would be a claim the database
/// does not back — the rail would say no while a direct write said yes. So
/// Purchasing is gated (its three repositories all demand `purchase.manage`)
/// and the others are not, until each one's writes are gated too.
String? _paneRequires(ManagementPane pane) => switch (pane) {
  ManagementPane.purchasing => PosCapability.purchaseManage,
  _ => null,
};

bool _permits(PosStaff admin, ManagementPane pane) {
  final needed = _paneRequires(pane);
  // `can` and not `capabilities`: the latter is the direct-grant set alone,
  // and an owner holds almost everything through their role.
  return needed == null || admin.can(needed);
}

enum ManagementPane {
  staff,
  menu,
  floor,
  money,
  purchasing,
  receipt,
  eta,
  roles,
  activity,
}

class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  late ManagementPane _pane = widget.initialPane;

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(signedInStaffProvider);

    // Watched rather than read once: a manager whose role is changed from
    // another till mid-session loses the screen on the next frame, which is
    // the same answer the database would give the next time they saved.
    if (admin == null || !admin.can(PosCapability.staffManage)) {
      return _LockedOut(
        onClose: widget.onClose,
        signedIn: admin,
        onSignedIn: (staff) =>
            ref.read(signedInStaffProvider.notifier).signIn(staff),
      );
    }

    // Two gates, and they ask different questions. The PIN pad asks WHO this
    // is. This asks for the back office's own database password — the till's
    // credential holds SELECT and nothing more, deliberately, so nothing on
    // this screen can save until an administrator supplies theirs.
    //
    // Held for the session and never written to disk: putting it on the same
    // machine as the till's password would hand back everything the split was
    // protecting.
    if (ref.watch(adminDbCredentialProvider) == null) {
      return _AdminCredentialGate(onClose: widget.onClose, admin: admin);
    }

    final panes = managementPanesFor(
      admin: admin,
      authorsItsOwnCatalogue:
          ref.watch(catalogAdminRepositoryProvider) != null,
    );

    // A pane this terminal or this person does not have is not a pane the body
    // may render: `initialPane` is a deep link and a deep link can outlive the
    // permission that justified it.
    final showing = panes.contains(_pane) ? _pane : panes.first;

    return Scaffold(
      backgroundColor: context.pos.page,
      body: SafeArea(
        child: Column(
          children: [
            _Header(admin: admin, onClose: widget.onClose),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Rail(
                    current: showing,
                    panes: panes,
                    onPick: (pane) => setState(() => _pane = pane),
                  ),
                  Expanded(
                    child: switch (showing) {
                      ManagementPane.staff => ManagementStaffPane(admin: admin),
                      ManagementPane.menu => ManagementMenuPane(admin: admin),
                      ManagementPane.floor => ManagementFloorPane(admin: admin),
                      ManagementPane.money => ManagementMoneyPane(admin: admin),
                      ManagementPane.purchasing =>
                        ManagementPurchasingPane(admin: admin),
                      ManagementPane.receipt => ManagementReceiptPane(
                        admin: admin,
                      ),
                      ManagementPane.eta => const ManagementEtaPane(),
                      ManagementPane.roles => ManagementRolesPane(admin: admin),
                      ManagementPane.activity => const ManagementActivityPane(),
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.admin, required this.onClose});

  final PosStaff admin;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
      decoration: BoxDecoration(
        color: context.pos.surface,
        border: Border(bottom: context.pos.resting),
      ),
      child: Row(
        children: [
          Text(strings.management, style: PosText.screenTitle(color: context.pos.ink)),
          const SizedBox(width: PosSpace.lg),
          Text(
            '${admin.name} · '
            '${admin.role?.displayName(strings.languageCode) ?? strings.noRole}',
            style: PosText.ui(size: 13, color: context.pos.muted),
          ),
          const Spacer(),
          PosButton(
            label: strings.backToTill,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.current,
    required this.panes,
    required this.onPick,
  });

  final ManagementPane current;

  /// Which panes this terminal actually has. Not `ManagementPane.values`: the Menu pane
  /// is offline-only.
  final List<ManagementPane> panes;
  final ValueChanged<ManagementPane> onPick;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: context.pos.surface,
        border: Border(right: context.pos.resting),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final pane in panes)
            _RailItem(
              label: managementPaneLabel(strings, pane).$1,
              hint: managementPaneLabel(strings, pane).$2,
              selected: pane == current,
              onTap: () => onPick(pane),
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? context.pos.accentSoft : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(
          border: Border(
            bottom: context.pos.hairline,
            // Elevation is a border in this design, so selection is too.
            left: selected
                ? context.pos.accentBorder
                : const BorderSide(color: Colors.transparent, width: 2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: PosText.ui(color: context.pos.inkWarm, 
                size: 14,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: PosSpace.xs),
            Text(
              hint,
              style: PosText.ui(
                size: 11.5,
                color: context.pos.muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// What somebody sees when they reach Management without the permission for it.
///
/// A PIN prompt rather than a closed door, because the person who *can* get in
/// is usually standing next to the person who cannot, and the alternative is
/// signing the cashier out of a till mid-shift to let a manager sign in.
class _LockedOut extends ConsumerStatefulWidget {
  const _LockedOut({
    required this.onClose,
    required this.onSignedIn,
    this.signedIn,
  });

  final VoidCallback onClose;
  final ValueChanged<PosStaff> onSignedIn;
  final PosStaff? signedIn;

  @override
  ConsumerState<_LockedOut> createState() => _LockedOutState();
}

class _LockedOutState extends ConsumerState<_LockedOut> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _digit(String digit) async {
    if (_pin.length >= PinRules.length || _busy) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length < PinRules.length) return;

    setState(() => _busy = true);
    final staff = await ref.read(staffDirectoryRepositoryProvider).byPin(_pin);
    if (!mounted) return;

    if (staff != null &&
        Authorization.check(staff, PosCapability.staffManage).isAllowed) {
      widget.onSignedIn(staff);
      return;
    }

    setState(() {
      _busy = false;
      _pin = '';
      // One message for "no such PIN" and "not a manager" alike. Telling them
      // apart would make the keypad a way of finding out who the managers are.
      _error = context.strings.pinCannotOpenManagement;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: context.pos.shell,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PosSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.management,
                  style: PosText.screenTitle(color: context.pos.shellText),
                ),
                const SizedBox(height: PosSpace.sm),
                Text(
                  widget.signedIn == null
                      ? strings.managementPinHelp
                      : '${strings.cannotManageStaff(widget.signedIn!.name)} '
                            '${strings.managementPinRetryHelp}',
                  style: PosText.ui(
                    size: 13,
                    color: context.pos.shellMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: PosSpace.xl),
                PinDots(length: _pin.length),
                const SizedBox(height: PosSpace.lg),
                PinPad(
                  onDigit: _digit,
                  onBackspace: () => setState(() {
                    if (_pin.isNotEmpty) {
                      _pin = _pin.substring(0, _pin.length - 1);
                    }
                  }),
                ),
                // The space is RESERVED, not conditional. Growing the column
                // when a refusal appears — and shrinking it again on the next
                // digit — moved the keypad under the finger already on its way
                // down, so the second attempt at a PIN landed on the wrong
                // keys. On a touchscreen at a counter that is not a cosmetic
                // problem; it is why the third attempt fails too.
                const SizedBox(height: PosSpace.md),
                SizedBox(
                  height: 18,
                  child: _error == null
                      ? null
                      : Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: PosText.ui(
                            size: 12.5,
                            color: context.pos.offlinePillText,
                          ),
                        ),
                ),
                const SizedBox(height: PosSpace.xl),
                PosButton(
                  label: strings.backToTill,
                  foreground: context.pos.shellText,
                  border: Border.fromBorderSide(context.pos.shellBorder),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the administrator database password, once per session.
///
/// Separate from the PIN pad on purpose: a PIN says who somebody is, and this
/// says which database role the writes run as. Conflating them would mean the
/// till credential could do everything a manager can, which is the boundary
/// `bin/pos_migrate.dart` refuses to cross when it grants.
class _AdminCredentialGate extends ConsumerStatefulWidget {
  const _AdminCredentialGate({required this.onClose, required this.admin});

  final VoidCallback onClose;
  final PosStaff admin;

  @override
  ConsumerState<_AdminCredentialGate> createState() =>
      _AdminCredentialGateState();
}

class _AdminCredentialGateState extends ConsumerState<_AdminCredentialGate> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Try the credential before accepting it.
  ///
  /// A password that is merely *stored* would fail later, on the first save,
  /// after the manager had typed a whole staff record — so it is proved here,
  /// against the real connection, while there is nothing to lose.
  Future<void> _submit() async {
    final value = _controller.text;
    if (value.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    ref.read(adminDbCredentialProvider.notifier).set(value);

    final failure = await ref
        .read(adminPosDatabaseProvider)
        .probe(ref.read(adminDeploymentProvider));

    if (!mounted) return;
    if (failure == null) return; // The screen rebuilds; the gate is gone.

    ref.read(adminDbCredentialProvider.notifier).forget();
    setState(() {
      _busy = false;
      final strings = context.strings;
      _error = switch (failure) {
        PosDbFailure.auth => strings.backOfficeAuthFailed(
          ref.read(adminDeploymentProvider).databaseUser,
        ),
        PosDbFailure.dns || PosDbFailure.tcp => strings.backOfficeUnreachable,
        _ => strings.backOfficeRefused,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: context.pos.shell,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PosSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.backOfficePassword,
                  textAlign: TextAlign.center,
                  style: PosText.ui(
                    size: 20,
                    weight: FontWeight.w700,
                    color: context.pos.shellText,
                  ),
                ),
                const SizedBox(height: PosSpace.sm),
                Text(
                  strings.backOfficePasswordHelp(widget.admin.name),
                  textAlign: TextAlign.center,
                  style: PosText.ui(
                    size: 12.5,
                    color: context.pos.shellMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: PosSpace.xl),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  autofocus: true,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  style: PosText.mono(size: 15, color: context.pos.shellText),
                  decoration: InputDecoration(
                    labelText: ref.read(adminDeploymentProvider).databaseUser,
                    labelStyle: PosText.mono(
                      size: 12,
                      color: context.pos.shellMuted,
                    ),
                    filled: true,
                    fillColor: context.pos.shellCard,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: PosSpace.md),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: PosText.ui(size: 12.5, color: context.pos.danger),
                  ),
                ],
                const SizedBox(height: PosSpace.xl),
                PosButton(
                  label: _busy ? strings.checking : strings.openManagement,
                  background: context.pos.accent,
                  foreground: Colors.white,
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: PosSpace.md),
                PosButton(
                  label: strings.backToTill,
                  foreground: context.pos.shellText,
                  border: Border.fromBorderSide(context.pos.shellBorder),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
