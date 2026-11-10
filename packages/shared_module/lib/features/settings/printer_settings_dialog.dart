import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/printer_config.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/repositories/repositories.dart';

/// The receipt printer and its drawer, changed without re-running setup.
///
/// The setup wizard was the only place a printer could be chosen, so a till
/// whose printer was swapped, or moved to another address, had to be reset to
/// point at the new one. Same choices the wizard offers, saved to the same
/// place — the terminal's own config file — so it survives a restart.
///
/// The till's Settings menu opens this; the back office hosts the same
/// [PrinterSettingsForm] as a pane.
class PrinterSettingsDialog extends StatelessWidget {
  const PrinterSettingsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const PrinterSettingsDialog(),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
      child: Padding(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: PrinterSettingsForm(
          onSaved: () => Navigator.of(context).pop(),
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}

/// Everything the printer dialog edits, without the dialog.
///
/// **One form for two hosts** — the till's Settings menu and the back office's
/// Settings › Printer pane. A second copy for the pane would be right on the
/// day it was written and wrong the first time somebody taught one of them
/// about a new paper width.
///
/// Its list of printers is [Flexible], so the host has to bound its height:
/// the dialog does with `maxHeight`, the pane by not putting it in a scroll
/// view.
class PrinterSettingsForm extends ConsumerStatefulWidget {
  const PrinterSettingsForm({required this.onSaved, this.onCancel, super.key});

  /// After the choice is in use and written to the config file.
  final VoidCallback onSaved;

  /// Null hides Cancel: a pane has nothing to close, and leaving it is how
  /// somebody throws a draft away.
  final VoidCallback? onCancel;

  @override
  ConsumerState<PrinterSettingsForm> createState() =>
      _PrinterSettingsFormState();
}

class _PrinterSettingsFormState extends ConsumerState<PrinterSettingsForm> {
  late PrinterConfig _draft = ref.read(printerConfigProvider);
  List<DiscoveredPrinter>? _printers;
  bool _scanning = false;
  bool _saving = false;
  String? _note;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _note = null;
    });
    final found = await ref.read(hardwarePortsProvider).discoverPrinters();
    if (!mounted) return;
    setState(() {
      _printers = found;
      _scanning = false;
    });
  }

  Future<void> _test() async {
    final name = _draft.name;
    if (name == null) return;
    final strings = context.strings;
    // The test page also kicks the drawer: proving it opens is half of what
    // somebody standing at a new printer is checking.
    final ok = await ref.read(hardwarePortsProvider).testPrint(name);
    if (!mounted) return;
    setState(
      () => _note = ok ? strings.testReceiptSent : strings.nothingPrinted,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    ref.read(printerConfigProvider.notifier).apply(_draft);
    try {
      final store = ref.read(terminalConfigStoreProvider);
      final saved = await store.read();
      // No saved config is a till still inside the wizard, which writes the
      // whole file — printer included — when it finishes.
      if (saved != null) await store.write(saved.copyWith(printer: _draft));
    } on Object {
      // The printer in use is already the new one; only the restart would
      // forget it, and the next save tries again.
    }
    if (!mounted) return;
    // Released for the pane, which stays open and may be saved again; the
    // dialog is gone by the next frame either way.
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final printers = [
      // The saved one stays choosable before a scan, and after one that did
      // not find it (switched off, or on another floor today).
      if (_draft.name case final current?
          when !(_printers ?? const []).any((p) => p.name == current))
        DiscoveredPrinter(
          name: current,
          transport: PrinterConfig.transportOf(current),
        ),
      ...?_printers,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.printerSettingsTitle,
          style: PosText.ui(size: 18, weight: FontWeight.w800, color: pos.ink),
        ),
        const SizedBox(height: PosSpace.sm),
        Text(
          strings.hardwareHelp,
          style: PosText.ui(size: 12.5, color: pos.muted, height: 1.5),
        ),
        const SizedBox(height: PosSpace.lg),
        Row(
          children: [
            PosButton(
              key: const Key('printer-find'),
              label: _scanning
                  ? strings.lookingForPrinters
                  : strings.findPrinters,
              border: Border.fromBorderSide(pos.resting),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              onPressed: _scanning ? null : _scan,
            ),
            const SizedBox(width: PosSpace.sm),
            PosButton(
              key: const Key('printer-test'),
              label: strings.testPrint,
              border: Border.fromBorderSide(pos.resting),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              onPressed: _draft.name == null ? null : _test,
            ),
          ],
        ),
        const SizedBox(height: PosSpace.md),
        Flexible(
          child: printers.isEmpty
              ? Text(
                  strings.printerNoneChosen,
                  style: PosText.ui(size: 13, color: pos.body),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final printer in printers)
                      _Choice(
                        key: Key('printer-${printer.name}'),
                        title: printer.name,
                        detail: printer.transport.toUpperCase(),
                        selected: _draft.name == printer.name,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(name: printer.name),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: PosSpace.lg),
        MicroLabel(strings.printerPaperWidth),
        const SizedBox(height: PosSpace.sm),
        Row(
          children: [
            for (final (width, label) in [
              (PrinterConfig.width80mm, strings.printerPaper80),
              (PrinterConfig.width58mm, strings.printerPaper58),
            ]) ...[
              Expanded(
                child: _Choice(
                  key: Key('printer-paper-$width'),
                  title: label,
                  selected: _draft.paperWidthDots == width,
                  onTap: () => setState(
                    () => _draft = _draft.copyWith(paperWidthDots: width),
                  ),
                ),
              ),
              if (width == PrinterConfig.width80mm)
                const SizedBox(width: PosSpace.sm),
            ],
          ],
        ),
        const SizedBox(height: PosSpace.lg),
        _Choice(
          key: const Key('printer-logo'),
          title: strings.printerPrintLogo,
          selected: _draft.printLogo,
          checkbox: true,
          onTap: () => setState(
            () => _draft = _draft.copyWith(printLogo: !_draft.printLogo),
          ),
        ),
        Text(
          strings.printerPrintLogoHint,
          style: PosText.ui(size: 12, color: pos.muted, height: 1.5),
        ),
        if (_note != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(_note!, style: PosText.ui(size: 12.5, color: pos.body)),
        ],
        const SizedBox(height: PosSpace.xl),
        Row(
          children: [
            if (widget.onCancel case final cancel?) ...[
              Expanded(
                child: PosButton(
                  label: strings.cancel,
                  border: Border.fromBorderSide(pos.resting),
                  onPressed: cancel,
                ),
              ),
              const SizedBox(width: PosSpace.sm),
            ],
            Expanded(
              child: PosButton(
                key: const Key('printer-save'),
                label: strings.save,
                background: pos.ink,
                foreground: pos.onInk,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One selectable row: a frame that turns accent when chosen.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
    this.checkbox = false,
  });

  final String title;
  final String? detail;
  final bool selected;

  /// A tick box rather than one of several round choices.
  final bool checkbox;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Padding(
      padding: const EdgeInsets.only(bottom: PosSpace.xs),
      child: Material(
        color: selected ? pos.accentSoft : pos.surface,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PosSpace.md,
              vertical: PosSpace.s10,
            ),
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                selected
                    ? BorderSide(color: pos.accent, width: 2)
                    : pos.resting,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  checkbox
                      ? (selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank)
                      : (selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                  size: 18,
                  color: selected ? pos.accent : pos.muted,
                ),
                const SizedBox(width: PosSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    style: PosText.ui(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: pos.ink,
                    ),
                  ),
                ),
                if (detail case final text? when text.isNotEmpty)
                  Text(text, style: PosText.mono(size: 11, color: pos.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
