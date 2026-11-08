import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import '../core/ui/theme.dart';
import '../core/ui/tokens.dart';
import '../core/ui/widgets/pos_widgets.dart';
import '../domain/models/permissions.dart';
import '../domain/services/authorization.dart';
import 'providers.dart';

/// The Excel button (BO-11), who may press it, and where the file goes. One
/// file, as the reports' providers are, so the feature lands — and could be
/// taken out — whole.

/// Whether the person acting may take a file away: `report.export`, through
/// [Authorization.check] — never `capabilities.contains`, which is direct
/// grants only and would refuse an owner whose role carries it.
///
/// **The person acting** ([actingStaffProvider]), as for `reports.view`:
/// inside Admin Mode, whoever came through its door, not whoever is signed in
/// at the till behind it.
final reportExportAllowedProvider = Provider.autoDispose<bool>(
  (ref) => Authorization.check(
    ref.watch(actingStaffProvider),
    PosCapability.reportExport,
  ).isAllowed,
);

/// Asks where to save [bytes] as [fileName], writes them there, and says
/// where that was — or null when the person cancelled.
typedef WorkbookSaver =
    Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
      required String dialogTitle,
    });

/// The desktop's save dialog. A provider so a widget test can stand in for a
/// dialog it cannot click; the default is the real one, never a fake.
final workbookSaverProvider = Provider<WorkbookSaver>(
  (ref) => saveWorkbookWithDialog,
);

/// `file_picker`'s save dialog, as the backup pane uses its folder picker.
/// On Windows and macOS the plugin writes the bytes itself once a place is
/// chosen — there is no second step here that could half-write a file.
Future<String?> saveWorkbookWithDialog({
  required String fileName,
  required Uint8List bytes,
  required String dialogTitle,
}) async {
  final saved = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    dialogTitle: dialogTitle,
  );
  if (saved == null) return null;
  return saved.scheme == 'file' ? saved.toFilePath() : '$saved';
}

/// Builds the file at the moment the button is pressed, in [strings]'
/// language and reading direction.
typedef WorkbookBuilder =
    Future<Uint8List> Function(AppStrings strings, bool rightToLeft);

/// "Export to Excel", and what became of the last press.
///
/// **Not drawn at all without `report.export`.** The key is critical, and a
/// critical control somebody lacks is hidden rather than greyed (§112): a
/// disabled Export is an invitation to go and find somebody who can. Asked
/// here, once, so Reports and the Sales list cannot come to disagree about
/// who sees it.
///
/// The words are said beside the button and not in a snack bar: the design
/// has no floating surfaces, and a path somebody needs to find the file again
/// should still be on screen when they look up.
class ExcelExportButton extends ConsumerStatefulWidget {
  const ExcelExportButton({
    required this.fileName,
    required this.build,
    super.key,
  });

  static const buttonKey = ValueKey('export-excel');
  static const noteKey = ValueKey('export-excel-note');

  final String fileName;
  final WorkbookBuilder build;

  @override
  ConsumerState<ExcelExportButton> createState() => _ExcelExportButtonState();
}

class _ExcelExportButtonState extends ConsumerState<ExcelExportButton> {
  bool _busy = false;
  String? _note;
  bool _failed = false;

  Future<void> _export() async {
    final strings = context.strings;
    // Read before the first await: the direction is the screen's, and the
    // screen may be gone by the time the file is.
    final rightToLeft = Directionality.of(context) == TextDirection.rtl;
    final save = ref.read(workbookSaverProvider);
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final bytes = await widget.build(strings, rightToLeft);
      final path = await save(
        fileName: widget.fileName,
        bytes: bytes,
        dialogTitle: strings.exportExcelDialogTitle,
      );
      if (!mounted) return;
      setState(() {
        _failed = false;
        // Cancelled is not news.
        _note = path == null ? null : strings.exportExcelSaved(path);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _note = strings.exportExcelFailed(
          error is StateError ? error.message : '$error',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(reportExportAllowedProvider)) return const SizedBox.shrink();
    final pos = context.pos;
    final note = _note;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible, and the caller puts this whole widget in a Flexible: a
        // path is as long as the folder somebody chose, and at the back
        // office's 1100 a fixed width for it pushed the Reports period row
        // 129 pixels past its edge. It gives way, and ellipsises, instead.
        if (note != null) ...[
          Flexible(
            child: Text(
              note,
              key: ExcelExportButton.noteKey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PosText.ui(
                size: 12,
                color: _failed ? pos.danger : pos.ok,
              ),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
        ],
        PosButton(
          key: ExcelExportButton.buttonKey,
          label: context.strings.exportExcel,
          height: PosSize.filterChip,
          border: Border.fromBorderSide(pos.resting),
          onPressed: _busy ? null : _export,
        ),
      ],
    );
  }
}
