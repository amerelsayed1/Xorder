import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import '../core/ui/theme.dart';
import 'providers.dart';
import 'router.dart';

class XorderPosApp extends ConsumerWidget {
  const XorderPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'XOrder POS',
        // Text direction follows from this. Flutter reads the locale and
        // wraps the tree in the right `Directionality`, so there is no
        // separate RTL switch to forget to set.
        locale: ref.watch(localeProvider),
        debugShowCheckedModeBanner: false,
        theme: buildPosTheme(),
        routerConfig: ref.watch(routerProvider),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      );
}
