import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/eta_submission.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';
import 'package:xorder_pos/domain/services/eta_serialization.dart';
import 'package:xorder_pos/features/admin/presentation/management_eta_pane.dart';

/// What the tax authority has not accepted yet, on screen.
///
/// The property under test is that the good state and the bad state do not
/// look alike. A queue growing where nobody looks is a failure mode this
/// codebase has already been bitten by once, and here the cost of not looking
/// is a fine.
void main() {
  final now = DateTime.utc(2026, 9, 8, 18);

  EtaSubmission row({
    int id = 1,
    String number = 'INV-0001',
    Duration ago = const Duration(hours: 1),
    EtaStatus status = EtaStatus.signed,
    String? error,
  }) => EtaSubmission(
    id: id,
    orderId: id,
    uuid: 'a' * 64,
    receiptNumber: number,
    issuedAt: now.subtract(ago),
    status: status,
    deviceSerial: 'TILL-1',
    errorMessage: error,
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pump(
    WidgetTester tester,
    List<EtaSubmission> rows, {
    String locale = 'en',
    EtaFilingSkipped? problem,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          etaQueueRepositoryProvider.overrideWithValue(_Queue(rows, now)),
          etaFilingProblemProvider.overrideWith(() => _Problem(problem)),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ManagementEtaPane(now: now)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('filing that has stopped is said above the queue', (
    tester,
  ) async {
    // An empty queue and a queue that stopped growing because nothing is
    // being filed look identical. The problem is what tells them apart.
    await pump(
      tester,
      const [],
      problem: const ProfileIncomplete([
        ProfileProblem(ProfileField.registrationNumber, 'nine digits'),
      ]),
    );

    expect(find.byKey(const Key('eta-filing-problem')), findsOneWidget);
    expect(
      find.text(
        'E-receipts are not being filed: the receipt profile has 1 thing to '
        'fix.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('and nothing is said when filing is working', (tester) async {
    await pump(tester, const []);
    expect(find.byKey(const Key('eta-filing-problem')), findsNothing);
  });

  testWidgets('an empty queue says so in one sentence', (tester) async {
    // The good state has to be readable at a glance, or nobody will glance.
    await pump(tester, const []);
    expect(find.text('Everything has been filed.'), findsOneWidget);
  });

  testWidgets('work in progress is counted without being an alarm', (
    tester,
  ) async {
    // A receipt rung up an hour ago and not yet sent is the normal state of a
    // working till. Colouring that red would teach everybody to ignore red.
    await pump(tester, [row()]);
    expect(find.text('1 receipt waiting'), findsOneWidget);
    expect(find.text('1 past their deadline'), findsNothing);
  });

  testWidgets('a late receipt is counted separately and named', (tester) async {
    await pump(tester, [row(ago: const Duration(hours: 30))]);
    expect(find.text('1 past its deadline'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
  });

  testWidgets('a receipt inside the window but close says due soon', (
    tester,
  ) async {
    await pump(tester, [row(ago: const Duration(hours: 21))]);
    expect(find.text('Due soon'), findsOneWidget);
    expect(find.text('Late'), findsNothing);
  });

  testWidgets('a refusal shows the authority\'s own words', (tester) async {
    // Verbatim. A paraphrase would be a paraphrase of the only sentence that
    // says how to fix it.
    await pump(tester, [
      row(status: EtaStatus.rejected, error: 'Invalid activity code 5610'),
    ]);
    expect(find.text('Refused'), findsOneWidget);
    expect(find.text('Invalid activity code 5610'), findsOneWidget);
  });

  testWidgets('every state has a sentence, not a wire value', (tester) async {
    await pump(tester, [
      row(id: 1, number: 'INV-1', status: EtaStatus.pending),
      row(id: 2, number: 'INV-2', status: EtaStatus.signed),
      row(id: 3, number: 'INV-3', status: EtaStatus.submitted),
    ]);

    expect(find.text('Not sealed'), findsOneWidget);
    expect(find.text('Ready to send'), findsOneWidget);
    expect(find.text('Sent, awaiting a verdict'), findsOneWidget);
    expect(find.textContaining('pending'), findsNothing);
  });

  testWidgets('the oldest receipt is named, in hours', (tester) async {
    await pump(tester, [
      row(id: 1, ago: const Duration(hours: 2)),
      row(id: 2, number: 'INV-2', ago: const Duration(hours: 9)),
    ]);
    expect(find.text('9h'), findsWidgets);
  });

  testWidgets('the deadline is measured against the clock passed in', (
    tester,
  ) async {
    // Not DateTime.now(): the summary and the rows must agree, and a test
    // that read the wall clock would pass today and fail in a year.
    await pump(tester, [row(ago: const Duration(hours: 23, minutes: 59))]);
    expect(find.text('Late'), findsNothing);

    await pump(tester, [row(ago: const Duration(hours: 24))]);
    expect(find.text('Late'), findsOneWidget);
  });

  testWidgets('a receipt number stays left to right in Arabic', (tester) async {
    await pump(tester, [row()], locale: 'ar');
    final number = find.text('INV-0001');
    expect(Directionality.of(tester.element(number)), TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });
}

class _Queue implements EtaQueueRepository {
  const _Queue(this._rows, this._now);

  final List<EtaSubmission> _rows;
  final DateTime _now;

  @override
  Future<List<EtaSubmission>> outstanding({int limit = 200}) async => _rows;

  @override
  Future<EtaQueueSummary> summary({required DateTime now}) async {
    final outstanding = _rows.where((r) => r.status.isOutstanding).toList();
    return EtaQueueSummary(
      outstanding: outstanding.length,
      rejected: outstanding.where((r) => r.status.needsAttention).length,
      late: outstanding.where((r) => r.isLate(_now)).length,
      oldest: outstanding.isEmpty
          ? null
          : outstanding
                .map((r) => r.issuedAt)
                .reduce((a, b) => a.isBefore(b) ? a : b),
    );
  }

  @override
  Future<EtaEnqueued> enqueue({
    required int orderId,
    required String deviceSerial,
    required String receiptNumber,
    required String receiptType,
    required DateTime issuedAt,
    required EtaObject Function(String previousUuid) build,
    int? refundId,
  }) => throw UnimplementedError();

  @override
  Future<String?> canonicalFor(int id) => throw UnimplementedError();

  @override
  Future<void> markSigned(int id, String signature) =>
      throw UnimplementedError();

  @override
  Future<void> markAccepted(
    int id, {
    required String submissionUuid,
    String? longId,
  }) => throw UnimplementedError();

  @override
  Future<void> markRejected(int id, String message) =>
      throw UnimplementedError();

  @override
  Future<void> markAttempted(int id, String message) =>
      throw UnimplementedError();
}

class _Problem extends EtaFilingProblem {
  _Problem(this._initial);

  final EtaFilingSkipped? _initial;

  @override
  EtaFilingSkipped? build() => _initial;
}
