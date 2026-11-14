import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/features/home/home_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

/// Close the day on the home screen is for whoever holds `day.close`, and only
/// while a day is open.
void main() {
  setUpAll(loadPosFonts);

  final openDay = BusinessDay(
    id: 1,
    date: DateTime(2026, 10, 26),
    openedAt: DateTime(2026, 10, 26, 6),
  );

  Future<void> pump(
    WidgetTester tester, {
    required PosStaff? staff,
    required bool dayOpen,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        businessDayProvider.overrideWith(
          (ref) async => dayOpen ? openDay : null,
        ),
      ],
    );
    addTearDown(container.dispose);
    if (staff != null) {
      container.read(signedInStaffProvider.notifier).signIn(staff);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: buildPosTheme(),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(onBack: () {}, onPick: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PosStaff staff(Set<String> capabilities) =>
      PosStaff(id: 7, name: 'Sam', capabilities: capabilities);

  final closeDay = find.byKey(const Key('home-close-day'));

  testWidgets('shown to staff with day.close while a day is open', (
    tester,
  ) async {
    await pump(tester, staff: staff({PosCapability.dayClose}), dayOpen: true);
    expect(closeDay, findsOneWidget);
    expect(find.text('Close the day'), findsOneWidget);
  });

  testWidgets('hidden from staff without day.close', (tester) async {
    await pump(tester, staff: staff({PosCapability.operate}), dayOpen: true);
    expect(closeDay, findsNothing);
  });

  testWidgets('hidden when nobody is signed in', (tester) async {
    await pump(tester, staff: null, dayOpen: true);
    expect(closeDay, findsNothing);
  });

  testWidgets('hidden when no day is open, even with the permission', (
    tester,
  ) async {
    await pump(tester, staff: staff({PosCapability.dayClose}), dayOpen: false);
    expect(closeDay, findsNothing);
  });
}
