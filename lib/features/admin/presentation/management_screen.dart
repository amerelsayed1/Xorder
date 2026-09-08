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
import 'management_money_pane.dart';
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
enum ManagementPane { staff, menu, floor, money, receipt, roles, activity }

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

    // Menu authoring exists only where this terminal is the author of its own
    // catalogue — offline. On a cloud till the platform authors it and the
    // bootstrap seeder overwrites whatever is here, so the pane would be an
    // invitation to lose work.
    // The three panes that exist only where this terminal authors its own
    // world. Named once, so adding a fourth cannot forget the gate.
    const authoring = {ManagementPane.menu, ManagementPane.floor, ManagementPane.money};

    final panes = [
      for (final pane in ManagementPane.values)
        // Both authoring panes exist only where this terminal is the author.
        if (!authoring.contains(pane) ||
            ref.watch(catalogAdminRepositoryProvider) != null)
          pane,
    ];

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
                    current: _pane,
                    panes: panes,
                    onPick: (pane) => setState(() => _pane = pane),
                  ),
                  Expanded(
                    child: switch (_pane) {
                      ManagementPane.staff => ManagementStaffPane(admin: admin),
                      ManagementPane.menu => ManagementMenuPane(admin: admin),
                      ManagementPane.floor => ManagementFloorPane(admin: admin),
                      ManagementPane.money => ManagementMoneyPane(admin: admin),
                      ManagementPane.receipt => ManagementReceiptPane(
                        admin: admin,
                      ),
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

  /// A function of the language rather than a const map: the rail is the one
  /// place in Management that names every pane, so it is the one place a pane
  /// added without an Arabic label has to fail to compile.
  static (String, String) _label(AppStrings s, ManagementPane pane) => switch (pane) {
    ManagementPane.staff => (s.paneStaff, s.paneStaffBlurb),
    ManagementPane.menu => (s.paneMenu, s.paneMenuBlurb),
    ManagementPane.floor => (s.floorPlan, s.floorPlanHint),
    ManagementPane.money => (s.moneyRules, s.moneyRulesHint),
    ManagementPane.receipt => (s.paneReceipt, s.paneReceiptBlurb),
    ManagementPane.roles => (s.paneRoles, s.paneRolesBlurb),
    ManagementPane.activity => (s.paneActivity, s.paneActivityBlurb),
  };

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
              label: _label(strings, pane).$1,
              hint: _label(strings, pane).$2,
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
