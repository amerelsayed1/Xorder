import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/tender_method.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';
import 'tender_type_dialog.dart';

/// How the restaurant takes money (§40).
///
/// Authored here on an offline till only. On a cloud till the platform is the
/// author (POS-BE-013): `BootstrapSeeder` writes these rows from the bundle,
/// and the drain sends a payment only if its tender is one the platform sent.
/// A method made here would be one the platform has never heard of, and every
/// sale taken on it would be held unsent — so on cloud the pane lists them,
/// operates nothing, and says where they come from. Same rule and same notice
/// as the order types.
class ManagementTendersPane extends ConsumerStatefulWidget {
  const ManagementTendersPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementTendersPane> createState() =>
      _ManagementTendersPaneState();
}

class _ManagementTendersPaneState extends ConsumerState<ManagementTendersPane> {
  bool _busy = false;
  String? _note;

  Future<void> _edit(TenderMethod? method) async {
    final repository = ref.read(catalogAdminRepositoryProvider);
    if (repository == null) return;

    final edited = await TenderTypeDialog.show(context, method: method);
    if (edited == null || !mounted) return;

    setState(() => _busy = true);
    final result = await repository.saveTenderType(edited, by: widget.admin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });

    // The payment screen reads this. Without the invalidation a cashier would
    // keep being offered a method that was retired a minute ago.
    if (result.succeeded) {
      ref
        ..invalidate(tenderTypesProvider)
        ..invalidate(tenderTypesAllProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final authors = ref.watch(catalogAdminRepositoryProvider) != null;

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        if (!authors) ...[
          PlatformOwnedNotice(text: strings.tenderTypesComeFromPlatform),
          const SizedBox(height: PosSpace.xl),
        ],
        PaneSection(title: strings.tenderTypes, hint: strings.tenderTypesHint),
        ...ref
            .watch(tenderTypesAllProvider)
            .when(
              loading: () => const [SizedBox(height: 40)],
              error: (error, _) => [
                Text(
                  '$error',
                  style: PosText.ui(size: 13, color: context.pos.danger),
                ),
              ],
              data: (methods) => [
                for (final method in methods)
                  _TenderRow(
                    method: method,
                    onEdit: authors && !_busy ? () => _edit(method) : null,
                  ),
              ],
            ),
        if (_note != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(_note!, style: PosText.ui(size: 12.5, color: context.pos.danger)),
        ],
        // Absent rather than disabled on cloud. It used to be shown there and
        // do nothing at all — `_edit` returned on the null repository — which
        // is a button that lies.
        if (authors) ...[
          const SizedBox(height: PosSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PosButton(
              key: const Key('tender-new'),
              label: strings.tenderNew,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: _busy ? null : () => _edit(null),
            ),
          ),
        ],
      ],
    );
  }
}

/// One payment method, as the editor lists them.
class _TenderRow extends StatelessWidget {
  const _TenderRow({required this.method, required this.onEdit});

  final TenderMethod method;

  /// Null while the pane is saving, or on a terminal whose payment methods
  /// belong to the platform.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.hairline),
        ),
        child: Opacity(
          // Retired methods stay listed, greyed. They have to: a manager who
          // turned one off needs a way to turn it back on.
          opacity: method.isActive ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  method.displayName(strings.languageCode),
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              if (!method.isActive)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  child: Text(
                    strings.tenderRetired,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ),
              if (method.countsAsCash)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PosSpace.sm,
                    vertical: 2,
                  ),
                  color: palette.okSoft,
                  child: Text(
                    strings.tenderCountsAsCash,
                    style: PosText.ui(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: palette.ok,
                    ),
                  ),
                ),
              const SizedBox(width: PosSpace.sm),
              MonoCode(method.code),
            ],
          ),
        ),
      ),
    );
  }
}
