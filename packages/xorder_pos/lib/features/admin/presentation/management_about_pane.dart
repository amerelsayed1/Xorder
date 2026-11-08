import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';
import '../../../domain/models/shift.dart';
import '../../settings/about_dialog.dart';

/// Settings › About XOrder: the till's About dialog, as a pane.
///
/// **The dialog's own content**, not a copy — see [PosAboutDetails]. Ungated,
/// as the till's Settings menu offers About to anybody signed in: a version
/// number is what support asks the person holding the phone, whoever they are.
class ManagementAboutPane extends StatelessWidget {
  const ManagementAboutPane({required this.admin, super.key});

  /// Unused today, and taken anyway so the shell builds every pane the same
  /// way — and so a later row that is not everybody's has somebody to ask.
  final PosStaff admin;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('about-pane'),
    padding: const EdgeInsets.all(PosSpace.xl),
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: const PosAboutDetails(),
        ),
      ),
    ],
  );
}
