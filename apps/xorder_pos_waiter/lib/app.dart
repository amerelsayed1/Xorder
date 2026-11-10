import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mode.dart';
import 'screens/floor_screen.dart';
import 'screens/sign_in_screen.dart';
import 'state.dart';
import 'theme.dart';

/// "XOrder Waiter" (waiter-app): table orders on a phone or tablet. The mode
/// — cloud or offline — is the build's, read from [waiterModeProvider], which
/// the entry point binds.
class WaiterApplication extends ConsumerWidget {
  const WaiterApplication({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(waiterModeProvider);
    final app = ref.watch(waiterAppProvider);
    return WaiterModeScope(
      mode: mode,
      child: MaterialApp(
        title: switch (mode) {
          WaiterMode.cloud => 'XOrder Waiter Cloud',
          WaiterMode.offline => 'XOrder Waiter Offline',
        },
        debugShowCheckedModeBanner: false,
        theme: buildWaiterTheme(),
        // Arabic: the language a waiter in Egypt reads fastest. There is no
        // switch on screen.
        locale: app.locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: switch (app.phase) {
          WaiterPhase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
          WaiterPhase.signedOut => const SignInScreen(),
          WaiterPhase.signedIn => const FloorScreen(),
        },
      ),
    );
  }
}
