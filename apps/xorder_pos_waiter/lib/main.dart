import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/connect_screen.dart';
import 'screens/floor_screen.dart';
import 'screens/pin_screen.dart';
import 'state.dart';
import 'theme.dart';

/// "XOrder Waiter" (waiter-app, WA1): table orders on a phone or tablet,
/// paired with the till that holds the tables.
void main() => runApp(const ProviderScope(child: WaiterApplication()));

class WaiterApplication extends ConsumerWidget {
  const WaiterApplication({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(waiterAppProvider);
    return MaterialApp(
      title: 'XOrder Waiter',
      debugShowCheckedModeBanner: false,
      theme: buildWaiterTheme(),
      // Arabic first: the language a waiter in Egypt reads fastest. One tap
      // on any screen switches.
      locale: app.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: switch (app.phase) {
        WaiterPhase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        WaiterPhase.unpaired => const ConnectScreen(),
        WaiterPhase.signedOut => const PinScreen(),
        WaiterPhase.signedIn => const FloorScreen(),
      },
    );
  }
}
