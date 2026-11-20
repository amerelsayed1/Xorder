import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/password_sign_in.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:xorder_pos_cloud/features/cloud_back_office_screen.dart';
import 'package:xorder_pos_test_support/fakes.dart';

/// tablet-cloud-onboarding, Stage 5: the Management screen offers "Change
/// business" to somebody who may manage terminals, and shows the refusal in
/// words. The refusals themselves are proved in shared_module's
/// `change_business_test.dart`; this is only the screen.
class _Platform implements PlatformPasswordCheck {
  _Platform(this.verdict);
  final PasswordVerdict verdict;

  @override
  Future<PasswordVerdict> verify({
    required String username,
    required String password,
  }) async => verdict;
}

void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Amer',
    username: 'amer',
    role: FakeSessionRepository.owner,
  );
  const cashier = PosStaff(
    id: 2,
    name: 'Rana A.',
    username: 'rana',
    role: FakeSessionRepository.cashier,
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required PosStaff staff,
    PasswordVerdict verdict = PasswordVerdict.rejected,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        platformPasswordCheckProvider.overrideWithValue(_Platform(verdict)),
      ],
    );
    addTearDown(container.dispose);
    container.read(signedInStaffProvider.notifier).signIn(staff);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: CloudBackOfficeScreen(onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a cashier is not offered it', (tester) async {
    await pump(tester, staff: cashier);
    expect(find.byKey(const Key('change-business')), findsNothing);
  });

  testWidgets('an owner sees it, and must confirm with a password', (
    tester,
  ) async {
    await pump(tester, staff: owner);

    expect(find.byKey(const Key('change-business')), findsOneWidget);
    expect(find.byKey(const Key('change-business-password')), findsNothing);

    await tester.tap(find.byKey(const Key('change-business')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('change-business-password')), findsOneWidget);
    expect(find.byKey(const Key('change-business-confirm')), findsOneWidget);
  });

  testWidgets('a wrong password is said, the field is cleared, nothing is '
      'changed', (tester) async {
    final container = await pump(tester, staff: owner);

    await tester.tap(find.byKey(const Key('change-business')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('change-business-password')),
      'bad',
    );
    await tester.tap(find.byKey(const Key('change-business-confirm')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('change-business-error'))).data,
      'That password is not right.',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('change-business-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(container.read(signedInStaffProvider), isNotNull);
  });

  testWidgets('Cancel closes the form and forgets what was typed', (
    tester,
  ) async {
    await pump(tester, staff: owner);

    await tester.tap(find.byKey(const Key('change-business')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('change-business-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('change-business-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('change-business-password')), findsNothing);
    expect(find.byKey(const Key('change-business')), findsOneWidget);
  });
}
