import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/deployment.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../data/cloud/cloud_provisioning_repository.dart' show posAppVersion;
import '../../data/postgres/pos_database.dart';

/// What support asks for first: which version, which till, which database.
///
/// The till's Settings menu opens this; the back office hosts the same
/// [PosAboutDetails] as Settings › About.
class PosAboutDialog extends StatelessWidget {
  const PosAboutDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const PosAboutDialog(),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PosAboutDetails(),
            const SizedBox(height: PosSpace.xl),
            PosButton(
              label: context.strings.close,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The About dialog's content, without the dialog.
///
/// **One list for two hosts**, so the version support reads off the back
/// office is the version the till's own menu would have said — a second copy
/// would be the one that forgot the terminal id.
///
/// Read off the screen over the phone, so every value is mono and left to
/// right in both languages — they are codes, not words.
class PosAboutDetails extends ConsumerWidget {
  const PosAboutDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final pos = context.pos;
    final config = ref.watch(deploymentProvider);
    final terminal = ref.watch(terminalProfileProvider);
    final session = ref.watch(sessionProvider).valueOrNull;
    final host = PosDatabase.hostFor(config);

    final rows = <(String, String)>[
      (strings.aboutVersion, posAppVersion),
      (
        strings.aboutMode,
        config.mode == DeploymentMode.offline
            ? strings.modeOffline
            : strings.modeCloud,
      ),
      if (session?.tenantName case final name? when name.isNotEmpty)
        (strings.tenantCell, name),
      if (terminal.branchName case final branch?) (strings.branchCell, branch),
      if (terminal.terminalName case final name?) (strings.terminalCell, name),
      if (terminal.terminalId case final id?) (strings.aboutTerminalId, id),
      if (host != null)
        (
          strings.aboutDatabase,
          '${config.databaseName} · $host:${config.databasePort}',
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'XOrder POS',
          style: PosText.ui(size: 20, weight: FontWeight.w800, color: pos.ink),
        ),
        const SizedBox(height: PosSpace.lg),
        for (final (label, value) in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
            decoration: BoxDecoration(
              border: Border(bottom: pos.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 130, child: MicroLabel(label)),
                Expanded(
                  child: SelectableText(
                    value,
                    textDirection: TextDirection.ltr,
                    style: PosText.mono(size: 13, color: pos.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
