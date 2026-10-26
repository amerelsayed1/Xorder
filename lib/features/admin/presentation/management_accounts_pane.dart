import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/financial_account.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/tender_method.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/repositories/repositories.dart' show PosBranch;
import 'admin_messages.dart';
import 'admin_pane_bits.dart';
import 'financial_account_dialog.dart';

/// Finance › Accounts (XORD-015, stage 1): where the business keeps its money,
/// and which account each payment method pays into.
///
/// **Nothing is booked to an account.** No sale, refund, shift or report reads
/// any of this yet; the pane says so, because an owner who sees "Bank — CIB"
/// next to "Card" will reasonably assume the card takings are being tracked
/// there, and they are not until stage 2.
///
/// Authored here on an offline till only. On a cloud till the platform is the
/// author: `BootstrapSeeder` replaces these rows from the bundle, so an account
/// made here would last until the next sync. The pane lists them, operates
/// nothing and says where they come from — the same rule and the same notice as
/// the payment methods. Absent rather than disabled: no button that lies.
class ManagementAccountsPane extends ConsumerStatefulWidget {
  const ManagementAccountsPane({required this.admin, super.key});

  /// The person in Admin Mode.
  final PosStaff admin;

  /// Read off the pane itself, like Settlements, so the bar can never ask less
  /// than the pane does. The repository refuses without it too.
  static const requires = {PosCapability.financeAccounts};

  @override
  ConsumerState<ManagementAccountsPane> createState() =>
      _ManagementAccountsPaneState();
}

class _ManagementAccountsPaneState
    extends ConsumerState<ManagementAccountsPane> {
  bool _busy = false;
  String? _note;

  void _reload() {
    ref
      ..invalidate(financialAccountsProvider)
      ..invalidate(tenderAccountDefaultsProvider);
  }

  Future<void> _edit(
    FinancialAccount? account,
    List<PosBranch> branches,
  ) async {
    final repository = ref.read(financialAccountsAdminRepositoryProvider);
    if (repository == null) return;

    // A refused rule reopens the dialog on what was typed, with the reason
    // inside it, instead of closing it and making the person retype.
    var draft = account;
    String? notice;
    while (true) {
      final edited = await FinancialAccountDialog.show(
        context,
        account: draft,
        branches: branches,
        notice: notice,
      );
      if (edited == null || !mounted) return;

      setState(() => _busy = true);
      final AdminResult<FinancialAccount> result;
      try {
        result = await repository.saveAccount(edited, by: widget.admin);
      } finally {
        // Whatever happened, the pane must not stay locked.
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;

      if (result.succeeded) {
        setState(() => _note = null);
        _reload();
        return;
      }

      final refusal = result.refusal!;
      // Only a broken rule is worth another go in the dialog; anything else
      // (not allowed, no credential, edited elsewhere) is said on the pane.
      if (refusal is! AccountRefused) {
        setState(() => _note = AdminText.refusal(context.strings, refusal));
        return;
      }
      draft = edited;
      notice = AdminText.refusal(context.strings, refusal);
    }
  }

  Future<void> _setDefault(
    TenderMethod method,
    int? branchId,
    int? accountId,
  ) async {
    final repository = ref.read(financialAccountsAdminRepositoryProvider);
    if (repository == null || _busy) return;

    setState(() => _busy = true);
    final AdminResult<TenderAccountDefault?> result;
    try {
      result = await repository.setDefault(
        tenderTypeId: method.id,
        branchId: branchId,
        accountId: accountId,
        by: widget.admin,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    setState(() {
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });
    if (result.succeeded) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final authors = ref.watch(financialAccountsAdminRepositoryProvider) != null;
    final branches =
        ref.watch(accountBranchesProvider).asData?.value ?? const <PosBranch>[];
    final accountsAsync = ref.watch(financialAccountsProvider);
    final defaults =
        ref.watch(tenderAccountDefaultsProvider).asData?.value ?? const [];
    final methods = [
      for (final m
          in ref.watch(tenderTypesAllProvider).asData?.value ??
              const <TenderMethod>[])
        if (m.isActive) m,
    ];

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        if (!authors) ...[
          PlatformOwnedNotice(text: strings.accountsComeFromPlatform),
          const SizedBox(height: PosSpace.xl),
        ],
        PaneSection(
          title: strings.paneFinanceAccounts,
          hint: strings.financeAccountsBlurb,
        ),
        ...accountsAsync.when(
          loading: () => const [SizedBox(height: 40)],
          error: (error, _) => [
            Text('$error', style: PosText.ui(size: 13, color: palette.danger)),
          ],
          data: (accounts) => [
            if (accounts.isEmpty) ...[
              Text(
                strings.accountsNone,
                key: const Key('accounts-none'),
                style: PosText.ui(
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                strings.accountsNoneHint,
                style: PosText.ui(size: 12.5, color: palette.muted),
              ),
            ],
            for (final account in accounts)
              _AccountRow(
                account: account,
                branches: branches,
                onEdit: authors && !_busy
                    ? () => _edit(account, branches)
                    : null,
              ),
            if (_note != null) ...[
              const SizedBox(height: PosSpace.md),
              Text(
                _note!,
                key: const Key('accounts-note'),
                style: PosText.ui(size: 12.5, color: palette.danger),
              ),
            ],
            if (authors) ...[
              const SizedBox(height: PosSpace.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: PosButton(
                  key: const Key('account-new'),
                  label: strings.accountsAdd,
                  border: Border.fromBorderSide(palette.resting),
                  onPressed: _busy ? null : () => _edit(null, branches),
                ),
              ),
            ],
            const SizedBox(height: PosSpace.xl),
            PaneSection(
              title: strings.accountsDefaultsTitle,
              hint: strings.accountsDefaultsHint,
            ),
            if (methods.isEmpty)
              Text(
                strings.accountsNoMethods,
                style: PosText.ui(size: 12.5, color: palette.muted),
              ),
            for (final method in methods)
              _DefaultsRow(
                method: method,
                accounts: [
                  for (final a in accounts)
                    if (a.isActive) a,
                ],
                allAccounts: accounts,
                defaults: defaults,
                branches: branches,
                onPick: authors && !_busy
                    ? (branch, id) => _setDefault(method, branch, id)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// One account, as the pane lists them.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.branches,
    required this.onEdit,
  });

  final FinancialAccount account;
  final List<PosBranch> branches;

  /// Null while saving, and on a terminal whose accounts belong to the
  /// platform.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    final where = account.branchId == null
        ? strings.accountAllBranches
        : branches
                  .where((b) => b.id == account.branchId)
                  .map((b) => b.name)
                  .firstOrNull ??
              '#${account.branchId}';

    return InkWell(
      key: Key('account-${account.id}'),
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.hairline),
        ),
        child: Opacity(
          // A switched-off account stays listed, greyed: whoever turned it off
          // needs a way to turn it back on.
          opacity: account.isActive ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  account.name,
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              if (!account.isActive)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  child: Text(
                    strings.tenderRetired,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ),
              Text(
                '${accountKindName(strings, account.kind)} · $where',
                style: PosText.ui(size: 12, color: palette.muted),
              ),
              if (account.referenceLabel != null) ...[
                const SizedBox(width: PosSpace.sm),
                MonoCode(account.referenceLabel!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Where one payment method pays in: the business-wide choice and, when there
/// is more than one branch, a choice per branch.
class _DefaultsRow extends StatelessWidget {
  const _DefaultsRow({
    required this.method,
    required this.accounts,
    required this.allAccounts,
    required this.defaults,
    required this.branches,
    required this.onPick,
  });

  final TenderMethod method;

  /// Active accounts, the ones that can be chosen.
  final List<FinancialAccount> accounts;

  /// All of them, so a choice that has since been switched off still shows by
  /// name rather than as a missing selection.
  final List<FinancialAccount> allAccounts;
  final List<TenderAccountDefault> defaults;
  final List<PosBranch> branches;

  /// Null when this till may not author (cloud, or no admin credential).
  final void Function(int? branchId, int? accountId)? onPick;

  int? _current(int? branchId) => defaults
      .where((d) => d.tenderTypeId == method.id && d.branchId == branchId)
      .map((d) => d.accountId)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    Widget scope({
      required int? branchId,
      required String label,
      required List<FinancialAccount> choices,
      required String noneLabel,
    }) {
      final current = _current(branchId);
      final currentName = allAccounts
          .where((a) => a.id == current)
          .map((a) => a.name)
          .firstOrNull;

      Widget chip(int? id, String text) {
        final selected = current == id;
        return PosButton(
          key: Key('default-${method.id}-${branchId ?? 'all'}-${id ?? 'none'}'),
          label: text,
          background: selected ? palette.ink : Colors.transparent,
          foreground: selected ? Colors.white : null,
          border: Border.fromBorderSide(palette.resting),
          onPressed: onPick == null || selected
              ? null
              : () => onPick!(branchId, id),
        );
      }

      // Read-only (cloud): the answer in words, no chips to press.
      if (onPick == null) {
        return Padding(
          padding: const EdgeInsets.only(top: PosSpace.xs),
          child: Text(
            '$label: ${currentName ?? noneLabel}',
            key: Key('default-text-${method.id}-${branchId ?? 'all'}'),
            style: PosText.ui(size: 12.5, color: palette.body),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(top: PosSpace.xs),
        child: Wrap(
          spacing: PosSpace.sm,
          runSpacing: PosSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label, style: PosText.ui(size: 12.5, color: palette.muted)),
            chip(null, noneLabel),
            for (final a in choices) chip(a.id, a.name),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      decoration: BoxDecoration(
        border: BorderDirectional(bottom: palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            method.displayName(strings.languageCode),
            style: PosText.ui(size: 13.5, color: palette.ink),
          ),
          // A business-wide default must be an account the whole business
          // shares; a branch's own account can only serve that branch.
          scope(
            branchId: null,
            label: branches.length > 1
                ? strings.accountsPaysIntoAll
                : strings.accountsPaysInto,
            choices: [
              for (final a in accounts)
                if (a.branchId == null) a,
            ],
            noneLabel: strings.accountsNoAccount,
          ),
          if (branches.length > 1)
            for (final branch in branches)
              scope(
                branchId: branch.id,
                label: branch.name,
                choices: [
                  for (final a in accounts)
                    if (a.branchId == null || a.branchId == branch.id) a,
                ],
                noneLabel: strings.accountsSameAsAll,
              ),
        ],
      ),
    );
  }
}
