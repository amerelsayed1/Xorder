import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../data/postgres/pos_database.dart'
    show PosDbException, PosDbFailure;

/// What the start screen shows when the till cannot open its database.
///
/// It used to print the exception — `PosDbException(missingDatabase):
/// Severity.fatal 3D000: database "…" does not exist` — in the middle of a black
/// screen with nothing to press. A business meets this after a disk fault, a
/// reset database server or a restored machine, and cannot be expected to read
/// it. So: one sentence on what is wrong, one on who can fix it, a button to try
/// again, and the technical text kept small underneath for whoever they call.
///
/// The sentences are for the person at the counter. The wizard's database
/// messages (firewall, `pg_hba`, a GRANT) are for the installer and say things
/// a cashier cannot act on.
class DatabaseUnavailable extends ConsumerWidget {
  const DatabaseUnavailable({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final pos = context.pos;
    final database = ref.watch(deploymentProvider).databaseName;

    final failure = error is PosDbException
        ? (error as PosDbException).failure
        : null;
    final message = switch (failure) {
      PosDbFailure.missingDatabase => strings.dbUnavailableMissing(database),
      PosDbFailure.dns || PosDbFailure.tcp => strings.dbUnavailableUnreachable,
      // Not "can't reach": it reached *something*, and that something could
      // not prove it was the business's server. Calling it a network fault
      // invites the one fix that must never be made from the counter —
      // turning encryption off — so the sentence says what happened and who
      // to call, and the till does not try again in the clear.
      PosDbFailure.tls => strings.dbUnavailableSecureConnection,
      PosDbFailure.auth ||
      PosDbFailure.missingRole ||
      PosDbFailure.permissionDenied => strings.dbUnavailableSignIn,
      _ => strings.dbUnavailableGeneric,
    };

    // The driver's own text for a database error, the plain `toString` for
    // anything else. Never the exception's class name.
    final details = error is PosDbException
        ? '${(error as PosDbException).raw}'
        : '$error';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.dbUnavailableTitle,
                textAlign: TextAlign.center,
                style: PosText.ui(
                  size: 22,
                  weight: FontWeight.w700,
                  color: pos.shellText,
                ),
              ),
              const SizedBox(height: PosSpace.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: PosText.ui(size: 14, color: pos.shellText, height: 1.6),
              ),
              const SizedBox(height: PosSpace.s28),
              PosButton(
                label: strings.tryAgain,
                height: 56,
                background: pos.accent,
                foreground: Colors.white,
                onPressed: onRetry,
              ),
              const SizedBox(height: PosSpace.s28),
              Text(
                strings.dbUnavailableDetails,
                textAlign: TextAlign.center,
                style: PosText.ui(size: 11, color: pos.shellMuted),
              ),
              const SizedBox(height: PosSpace.sm),
              Text(
                details,
                key: const Key('start-error-details'),
                textAlign: TextAlign.center,
                style: PosText.mono(size: 11, color: pos.shellMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
