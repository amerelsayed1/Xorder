import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/financial_account.dart';
import '../../../domain/repositories/repositories.dart' show PosBranch;

/// The word for a kind of account, in the till's language.
String accountKindName(AppStrings s, AccountKind kind) => switch (kind) {
  AccountKind.cash => s.accountKindCash,
  AccountKind.bank => s.accountKindBank,
  AccountKind.wallet => s.accountKindWallet,
};

/// Authoring one financial account (XORD-015, stage 1).
///
/// Offline tills only; the pane never offers it on a cloud till, where the
/// platform is the author. [branches] are this restaurant's, for tying an
/// account to one of them. Left on "All branches" the account is shared by the
/// whole business, which is what a company bank account is.
///
/// **The branch choice is shown only when it can matter**: with more than one
/// branch, or for an account that is already tied to one. On a single-location
/// business a branch-tied account could never be chosen as a payment method's
/// default (the business-wide choice takes shared accounts only), so offering
/// the choice would let the owner build something unusable.
class FinancialAccountDialog extends StatefulWidget {
  const FinancialAccountDialog({
    super.key,
    this.account,
    this.branches = const [],
    this.notice,
  });

  /// Null creates a new one. An account with `id == 0` is also a NEW one: it
  /// carries what the person typed before a refusal, so they can fix it
  /// without retyping.
  final FinancialAccount? account;
  final List<PosBranch> branches;

  /// Why the last attempt was refused, shown inside the dialog so the typed
  /// values are still in front of the person.
  final String? notice;

  static Future<FinancialAccount?> show(
    BuildContext context, {
    FinancialAccount? account,
    List<PosBranch> branches = const [],
    String? notice,
  }) => showDialog<FinancialAccount>(
    context: context,
    builder: (_) => FinancialAccountDialog(
      account: account,
      branches: branches,
      notice: notice,
    ),
  );

  @override
  State<FinancialAccountDialog> createState() => _FinancialAccountDialogState();
}

class _FinancialAccountDialogState extends State<FinancialAccountDialog> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _reference = TextEditingController(
    text: widget.account?.referenceLabel ?? '',
  );

  late AccountKind _kind = widget.account?.kind ?? AccountKind.cash;
  late int? _branchId = widget.account?.branchId;
  late bool _isActive = widget.account?.isActive ?? true;

  bool get _isNew => widget.account == null || widget.account!.id == 0;

  bool get _showBranchChoice =>
      widget.branches.length > 1 || widget.account?.branchId != null;

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _save() {
    final reference = _reference.text.trim();
    Navigator.of(context).pop(
      FinancialAccount(
        id: widget.account?.id ?? 0,
        name: _name.text.trim(),
        kind: _kind,
        branchId: _branchId,
        currency: widget.account?.currency,
        referenceLabel: reference.isEmpty ? null : reference,
        isActive: _isActive,
        sortOrder: widget.account?.sortOrder ?? 99,
      ),
    );
  }

  Widget _choice({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.pos;
    return PosButton(
      key: key,
      label: label,
      background: selected ? palette.ink : Colors.transparent,
      foreground: selected ? Colors.white : null,
      border: Border.fromBorderSide(palette.resting),
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isNew ? strings.accountsAdd : strings.accountsEdit,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.lg),

              MicroLabel(strings.accountName),
              const SizedBox(height: PosSpace.xs),
              TextField(
                key: const Key('account-name'),
                controller: _name,
                maxLength: 120,
                style: PosText.ui(size: 15, color: palette.ink),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: PosSpace.md),

              MicroLabel(strings.accountType),
              const SizedBox(height: PosSpace.xs),
              Wrap(
                spacing: PosSpace.sm,
                runSpacing: PosSpace.sm,
                children: [
                  for (final kind in AccountKind.values)
                    _choice(
                      key: Key('account-kind-${kind.wire}'),
                      label: accountKindName(strings, kind),
                      selected: kind == _kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                ],
              ),

              if (_showBranchChoice) ...[
                const SizedBox(height: PosSpace.md),
                MicroLabel(strings.accountBranch),
                const SizedBox(height: PosSpace.xs),
                Wrap(
                  spacing: PosSpace.sm,
                  runSpacing: PosSpace.sm,
                  children: [
                    _choice(
                      key: const Key('account-branch-all'),
                      label: strings.accountAllBranches,
                      selected: _branchId == null,
                      onTap: () => setState(() => _branchId = null),
                    ),
                    for (final branch in widget.branches)
                      _choice(
                        key: Key('account-branch-${branch.id}'),
                        label: branch.name,
                        selected: _branchId == branch.id,
                        onTap: () => setState(() => _branchId = branch.id),
                      ),
                  ],
                ),
                const SizedBox(height: PosSpace.xs),
                Text(
                  strings.accountBranchHint,
                  style: PosText.ui(size: 11.5, color: palette.muted),
                ),
              ],

              const SizedBox(height: PosSpace.md),
              MicroLabel(strings.accountReferenceLabel),
              const SizedBox(height: PosSpace.xs),
              TextField(
                key: const Key('account-reference'),
                controller: _reference,
                maxLength: 40,
                textDirection: TextDirection.ltr,
                style: PosText.mono(size: 15, color: palette.ink),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                strings.accountReferenceHint,
                style: PosText.ui(size: 11.5, color: palette.muted),
              ),

              if (!_isNew)
                SwitchListTile(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.accountSwitchOn,
                    style: PosText.ui(size: 13.5, color: palette.body),
                  ),
                ),

              if (widget.notice != null) ...[
                const SizedBox(height: PosSpace.md),
                Text(
                  widget.notice!,
                  key: const Key('account-notice'),
                  style: PosText.ui(size: 12.5, color: palette.danger),
                ),
              ],

              const SizedBox(height: PosSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      key: const Key('account-save'),
                      label: strings.save,
                      background: palette.ink,
                      foreground: palette.onInk,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
