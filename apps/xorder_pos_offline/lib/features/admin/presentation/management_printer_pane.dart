import 'package:flutter/material.dart';

import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/services/authorization.dart';
import 'package:shared_module/features/settings/printer_settings_dialog.dart';
import 'admin_pane_bits.dart';

/// Settings › Printer & cash drawer: the till's printer dialog, as a pane.
///
/// **The dialog's own form**, not a copy of it — see [PrinterSettingsForm].
///
/// Behind `terminal.manage`, the capability the till's Settings menu asks
/// before it offers the dialog. The printer is a fact about this machine, and
/// the person who may reset the machine is the person who may re-point it.
class ManagementPrinterPane extends StatelessWidget {
  const ManagementPrinterPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  Widget build(BuildContext context) {
    if (!Authorization.check(admin, PosCapability.terminalManage).isAllowed) {
      return PaneMessage(
        key: const Key('printer-pane-refused'),
        text: context.strings.printerNotYours,
      );
    }
    // Not a ListView: the form's printer list is Flexible and needs a bounded
    // height to flex within, which a scroll view would take away.
    return Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: PrinterSettingsForm(
            key: const Key('printer-pane'),
            onSaved: () => posToast(context, context.strings.printerSaved),
          ),
        ),
      ),
    );
  }
}
