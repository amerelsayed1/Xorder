import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';

/// The only screen on a machine the *other* app set up (pos-split-apps, BR-8).
///
/// One app per machine: "XOrder POS - Cloud" does not open a `config.json`
/// that "XOrder POS - Offline" wrote, and the other way round. The router
/// parks the till here whenever `TerminalBoot.otherAppMode` is set, and offers
/// no way on — not the wizard, whose chord would open a setup seeded from a
/// configuration this app must not touch. The words name the app that owns the
/// machine and what to do about it; nothing on this screen changes anything.
///
/// Like the welcome screen it follows the room's light or dark, for the same
/// reason: there is no counter and no shift here, just a machine in a room.
class WrongAppScreen extends ConsumerWidget {
  const WrongAppScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final installed =
        ref.watch(terminalSeedProvider).otherAppMode ?? DeploymentMode.cloud;
    final thisApp = ref.watch(appTitleProvider);

    return Scaffold(
      backgroundColor: context.pos.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(PosSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.wrongAppTitle,
                  style: PosText.ui(
                    size: 22,
                    weight: FontWeight.w600,
                    color: context.pos.ink,
                  ),
                ),
                const SizedBox(height: PosSpace.md),
                Text(
                  s.wrongAppBody(installed.productName, thisApp),
                  style: PosText.ui(size: 14, color: context.pos.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
