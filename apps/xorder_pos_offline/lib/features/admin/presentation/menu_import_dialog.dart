import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/mono_amount.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/data/import/spreadsheet_reader.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/menu_import.dart';
import 'package:xorder_pos/features/admin_mode/admin_messages.dart';

/// A spreadsheet the operator chose, already read into rows.
class MenuFile {
  const MenuFile(this.name, this.rows);

  /// The file's own name, shown so the operator can see they picked the one
  /// they meant. Not the path: a path is too long for a dialog header and
  /// nobody reads it.
  final String name;

  final List<List<String>> rows;
}

/// Choosing and reading a file, as one step.
///
/// One typedef rather than two because a widget test has no file dialog *and*
/// no file; substituting the pair together is what lets the whole preview and
/// apply path be tested without either.
typedef MenuFileSource = Future<MenuFile?> Function();

/// Importing a menu from a spreadsheet.
///
/// **Read, show, then apply — never read and apply.** A business hands over
/// four hundred rows and the operator has no way to know what is in them; a
/// dialog that imported on the strength of a file name would be asking someone
/// to approve something they cannot see. So this shows what it would do first,
/// in the terms that matter: how many items appear, how many prices move, which
/// categories get invented — and it names the price changes individually,
/// because "changes 40 items" is not a sentence anybody can approve.
class MenuImportDialog extends ConsumerStatefulWidget {
  const MenuImportDialog({super.key, required this.admin, this.source});

  final PosStaff admin;

  /// Null means the real file dialog. Tests pass their own.
  final MenuFileSource? source;

  /// The two buttons a test drives. Keys rather than labels because the
  /// labels are translated and the counts move.
  static const chooseKey = Key('menu-import-choose');
  static const applyKey = Key('menu-import-apply');

  /// Returns what was imported, or null if nothing was.
  static Future<MenuImportOutcome?> show(
    BuildContext context, {
    required PosStaff admin,
    MenuFileSource? source,
  }) => showDialog<MenuImportOutcome>(
    context: context,
    builder: (_) => MenuImportDialog(admin: admin, source: source),
  );

  @override
  ConsumerState<MenuImportDialog> createState() => _MenuImportDialogState();
}

class _MenuImportDialogState extends ConsumerState<MenuImportDialog> {
  MenuImportPlan? _plan;
  String? _fileName;
  String? _error;
  bool _busy = false;

  Future<MenuFile?> _pick() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: SpreadsheetReader.extensions,
    );
    final path = picked?.path;
    if (path == null) return null;
    return MenuFile(picked!.name, await SpreadsheetReader.read(path));
  }

  Future<void> _choose() async {
    setState(() {
      _busy = true;
      _error = null;
      _plan = null;
    });

    try {
      final file = await (widget.source ?? _pick)();
      if (!mounted) return;
      if (file == null) {
        setState(() => _busy = false);
        return;
      }

      final catalog = await ref.read(catalogRepositoryProvider).load();
      if (!mounted) return;

      // A menu that already has products settles the currency; the import
      // never gets to introduce a second one.
      final money = catalog.products.firstOrNull?.price;

      setState(() {
        _busy = false;
        _fileName = file.name;
        _plan = MenuImport.read(
          file.rows,
          existing: catalog.products,
          categories: catalog.categories,
          currency: money?.currency ?? 'EGP',
          exponent: money?.exponent ?? 2,
        );
      });
    } on SpreadsheetUnreadable catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _apply(MenuImportPlan plan) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(catalogAdminRepositoryProvider)!
        .importMenu(plan, by: widget.admin);

    if (!mounted) return;
    if (result.succeeded) {
      // Everything that reads the menu is now stale.
      ref.invalidate(catalogProvider);
      Navigator.of(context).pop(result.value);
      return;
    }

    setState(() {
      _busy = false;
      _error = AdminText.refusal(context.strings, result.refusal!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final plan = _plan;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogCount),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(strings, palette),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(PosSpace.lg),
                child: _body(strings, palette, plan),
              ),
            ),
            _footer(strings, palette, plan),
          ],
        ),
      ),
    );
  }

  Widget _header(AppStrings strings, PosPalette palette) => Container(
    padding: const EdgeInsets.all(PosSpace.lg),
    decoration: BoxDecoration(
      border: BorderDirectional(bottom: palette.resting),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.menuImportTitle,
          style: PosText.ui(
            size: 20,
            weight: FontWeight.w800,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: PosSpace.xs),
        if (_fileName != null)
          MonoCode(_fileName!, size: 12.5)
        else
          Text(
            strings.menuImportExplain,
            style: PosText.ui(size: 12.5, color: palette.muted),
          ),
      ],
    ),
  );

  Widget _body(AppStrings strings, PosPalette palette, MenuImportPlan? plan) {
    if (_busy) {
      return Column(
        children: [
          const SizedBox(height: PosSpace.lg),
          CircularProgressIndicator(color: palette.accent),
          const SizedBox(height: PosSpace.md),
          Text(
            strings.menuImportReading,
            style: PosText.ui(size: 13, color: palette.muted),
          ),
        ],
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(PosSpace.md),
        color: palette.dangerSoft,
        child: Text(
          _error!,
          style: PosText.ui(size: 13, color: palette.danger, height: 1.5),
        ),
      );
    }

    if (plan == null) return _instructions(strings, palette);
    if (plan.hasProblems) return _problems(strings, palette, plan);
    return _preview(strings, palette, plan);
  }

  Widget _instructions(AppStrings strings, PosPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        strings.menuImportExplain,
        style: PosText.ui(size: 13.5, color: palette.body, height: 1.5),
      ),
      const SizedBox(height: PosSpace.md),
      // The header the file needs, so a business knows what to send back.
      Container(
        padding: const EdgeInsets.all(PosSpace.sm),
        decoration: BoxDecoration(border: Border.fromBorderSide(palette.resting)),
        child: MonoCode(MenuImport.templateHeader.join(', ')),
      ),
      const SizedBox(height: PosSpace.md),
      Text(
        // Said before the file is chosen, not after. It is the question an
        // operator has before they dare press anything.
        strings.menuImportNeverDeletes,
        style: PosText.ui(size: 12.5, color: palette.muted),
      ),
    ],
  );

  Widget _problems(
    AppStrings strings,
    PosPalette palette,
    MenuImportPlan plan,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(PosSpace.sm),
        color: palette.dangerSoft,
        child: Text(
          // Nothing is applied while any row is wrong: half a menu is worse
          // than none, because nobody can tell which half landed.
          '${strings.menuImportProblemsTitle} · '
          '${strings.menuImportProblemsCount(plan.problems.length)}',
          style: PosText.ui(
            size: 13,
            weight: FontWeight.w700,
            color: palette.danger,
          ),
        ),
      ),
      const SizedBox(height: PosSpace.sm),
      for (final problem in plan.problems.take(40))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                // The line as the spreadsheet numbers it, so somebody can go
                // and look at it.
                child: MonoCode(strings.menuImportLine(problem.lineNumber)),
              ),
              Expanded(
                child: Text(
                  problem.message,
                  style: PosText.ui(size: 12.5, color: palette.body),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _preview(AppStrings strings, PosPalette palette, MenuImportPlan plan) {
    final creates = plan.creates.length;
    final updates = plan.updates.length;
    final unchanged = plan.unchanged.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.isEmpty)
          Container(
            padding: const EdgeInsets.all(PosSpace.md),
            color: palette.accentSoft,
            child: Text(
              strings.menuImportNothingToDo,
              style: PosText.ui(size: 13, color: palette.inkWarm),
            ),
          )
        else ...[
          if (creates > 0) _line(palette, strings.menuImportWillCreate(creates)),
          if (updates > 0) _line(palette, strings.menuImportWillUpdate(updates)),
          if (unchanged > 0)
            _line(palette, strings.menuImportUnchanged(unchanged), quiet: true),
          if (plan.newCategories.isNotEmpty)
            _line(
              palette,
              strings.menuImportNewCategories(plan.newCategories.join('، ')),
            ),
        ],
        const SizedBox(height: PosSpace.md),
        Text(
          strings.menuImportNeverDeletes,
          style: PosText.ui(size: 12.5, color: palette.muted),
        ),
        if (updates > 0) ...[
          const SizedBox(height: PosSpace.lg),
          MicroLabel(strings.menuImportWillUpdate(updates)),
          const SizedBox(height: PosSpace.xs),
          for (final row in plan.updates.take(25))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.nameEn,
                      overflow: TextOverflow.ellipsis,
                      style: PosText.ui(size: 12.5, color: palette.ink),
                    ),
                  ),
                  Text(
                    row.changes.join(', '),
                    style: PosText.ui(size: 11.5, color: palette.warn),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  MonoAmount(row.price, size: 12.5),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _line(PosPalette palette, String text, {bool quiet = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text(
      text,
      style: PosText.ui(
        size: 14,
        weight: quiet ? FontWeight.w400 : FontWeight.w700,
        color: quiet ? palette.muted : palette.ink,
      ),
    ),
  );

  Widget _footer(AppStrings strings, PosPalette palette, MenuImportPlan? plan) {
    final ready = plan != null && plan.canApply && !_busy;
    final count = plan == null
        ? 0
        : plan.creates.length + plan.updates.length;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(border: BorderDirectional(top: palette.resting)),
      child: Row(
        children: [
          Expanded(
            child: PosButton(
              label: strings.cancel,
              border: Border.fromBorderSide(palette.resting),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: PosButton(
              key: MenuImportDialog.chooseKey,
              label: strings.menuImportChooseFile,
              border: Border.fromBorderSide(palette.resting),
              onPressed: _busy ? null : _choose,
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            flex: 2,
            child: PosButton(
              key: MenuImportDialog.applyKey,
              label: strings.menuImportApply(count),
              background: ready ? palette.accent : palette.ctaDisabled,
              foreground: Colors.white,
              fontWeight: FontWeight.w700,
              onPressed: ready ? () => _apply(plan) : null,
            ),
          ),
        ],
      ),
    );
  }
}
