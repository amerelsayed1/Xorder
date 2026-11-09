import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// Switches between Arabic and English. Every screen carries it: a waiter who
/// picks up a handheld set to the other language must not need a menu to fix it.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    onPressed: ref.read(waiterAppProvider.notifier).toggleLanguage,
    child: Text(WaiterStrings.of(context).languageToggle),
  );
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(WaiterSpace.md),
    decoration: const BoxDecoration(
      color: WaiterColors.dangerSoft,
      border: Border.fromBorderSide(BorderSide(color: WaiterColors.danger)),
    ),
    child: Text(message, style: const TextStyle(color: WaiterColors.danger, fontWeight: FontWeight.w600)),
  );
}

class SmallSpinner extends StatelessWidget {
  const SmallSpinner({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: WaiterColors.ink));
}

/// "1234.50 EGP" — the till's figure in the till's currency, never recomputed
/// here. Arabic gets the Egyptian pound's own label, as on the till's receipts.
String moneyText(WaiterCurrency currency, int minor, {required bool arabic}) =>
    '${currency.of(minor).format()} ${arabic && currency.code == 'EGP' ? 'ج.م' : currency.code}';
