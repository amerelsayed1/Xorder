import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/catalog.dart';
import '../../../domain/models/receipt_profile.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/tender_method.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/services/ticket_engine.dart';
import '../../receipt/receipt_data.dart';
import '../../receipt/receipt_paper.dart';
import 'admin_messages.dart';

/// Who the receipt says sold the food.
///
/// **Two audiences, one form.** The top block is what a customer reads off the
/// paper. The bottom block is what Egypt's tax authority checks, and it is
/// separated and labelled as such rather than mixed in, because the two have
/// very different consequences: a missing footer note is a blank line, and a
/// missing registration number is a receipt that cannot be filed.
///
/// The form **saves while it is still incomplete**, on purpose. A restaurant
/// fills this in over several sittings — somebody types the trade name today
/// and rings the accountant about the activity code next week — so a form that
/// demanded all fourteen fields before it would accept any of them would be a
/// form that lost the first thirteen.
///
/// **The slip is beside the form**, drawn by the same `ReceiptPaper` a real
/// receipt is, from what is in the boxes right now. A restaurant deciding how
/// its name and address read on paper should not have to save, ring a sale and
/// print one to find out.
class ManagementReceiptPane extends ConsumerStatefulWidget {
  const ManagementReceiptPane({
    required this.admin,
    this.sections = const [],
    super.key,
  });

  final PosStaff admin;

  /// The rest of Settings › General, under the form (BO-8): this terminal's
  /// appearance and the backup summary.
  ///
  /// **Handed in rather than built here**, so this pane stays the company
  /// form and nothing else — the one `receipt_profile_ui_test.dart` pumps on
  /// its own — and General is the screen that composes it. In the form's own
  /// scroll rather than a second one around it: a list inside a list is two
  /// scrollbars and a wheel that moves whichever the pointer happens to be
  /// over. Each section saves itself; the form's Save is the form's alone, as
  /// plan 19 §2.6 asks, because the three have different gates and only the
  /// profile is revisioned.
  final List<Widget> sections;

  @override
  ConsumerState<ManagementReceiptPane> createState() =>
      _ManagementReceiptPaneState();
}

class _ManagementReceiptPaneState extends ConsumerState<ManagementReceiptPane> {
  final _controllers = <String, TextEditingController>{};
  ReceiptProfile? _loaded;
  bool _busy = false;
  String? _note;

  /// Creates every box, once, from the stored profile.
  ///
  /// **All of them, before anything reads one.** The ETA banner is computed
  /// from what is in the boxes, and a build that created them lazily as the
  /// widgets were constructed would compute it against fourteen empty strings
  /// and tell a fully configured branch it was incomplete — on the first paint,
  /// every time the pane opened.
  void _seed(ReceiptProfile base) {
    if (_controllers.isNotEmpty) return;
    final initial = <String, String>{
      ProfileField.tradeName: base.tradeName,
      ProfileField.registrationNumber: base.registrationNumber,
      ProfileField.activityCode: base.activityCode,
      ProfileField.branchCode: base.branchCode,
      ProfileField.country: base.address.country,
      ProfileField.governate: base.address.governate,
      ProfileField.regionCity: base.address.regionCity,
      ProfileField.street: base.address.street,
      ProfileField.buildingNumber: base.address.buildingNumber,
      'postal_code': base.address.postalCode ?? '',
      'floor': base.address.floor ?? '',
      'room': base.address.room ?? '',
      'landmark': base.address.landmark ?? '',
      'additional_info': base.address.additionalInformation ?? '',
      'phone': base.phone ?? '',
      'header_note': base.headerNote ?? '',
      'footer_note': base.footerNote ?? '',
    };
    for (final entry in initial.entries) {
      _controllers[entry.key] = TextEditingController(text: entry.value);
    }
  }

  TextEditingController _box(String field) => _controllers[field]!;

  String _text(String field) => _controllers[field]?.text.trim() ?? '';

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ReceiptProfile _edited(ReceiptProfile base) => base.copyWith(
    tradeName: _text(ProfileField.tradeName),
    registrationNumber: _text(ProfileField.registrationNumber),
    activityCode: _text(ProfileField.activityCode),
    branchCode: _text(ProfileField.branchCode),
    address: base.address.copyWith(
      country: _text(ProfileField.country),
      governate: _text(ProfileField.governate),
      regionCity: _text(ProfileField.regionCity),
      street: _text(ProfileField.street),
      buildingNumber: _text(ProfileField.buildingNumber),
      postalCode: _text('postal_code'),
      floor: _text('floor'),
      room: _text('room'),
      landmark: _text('landmark'),
      additionalInformation: _text('additional_info'),
    ),
    phone: _text('phone'),
    headerNote: _text('header_note'),
    footerNote: _text('footer_note'),
  );

  Future<void> _save(ReceiptProfile base) async {
    final repository = ref.read(receiptProfileRepositoryProvider);
    if (repository == null || _busy) return;

    setState(() {
      _busy = true;
      _note = null;
    });

    final result = await repository.save(
      _edited(base),
      by: widget.admin,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = result.succeeded
          ? context.strings.receiptProfileSaved
          : AdminText.refusal(context.strings, result.refusal!);
      // The saved profile carries the bumped revision. Without taking it the
      // next save would be refused as an edit from elsewhere — by this pane,
      // against itself.
      if (result.succeeded) _loaded = result.value;
    });

    // The slip reads this on every settlement.
    if (result.succeeded) ref.invalidate(receiptProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final repository = ref.watch(receiptProfileRepositoryProvider);
    if (repository == null) {
      return _withSections(_Centred(text: strings.receiptProfileNoDatabase));
    }

    final stored = ref.watch(receiptProfileProvider);

    // Once the form is up it stays up.
    //
    // A save invalidates `receiptProfileProvider` — the slip has to re-read
    // it — and that provider is watched here too, so the naive `.when` would
    // drop the operator's fourteen filled-in boxes behind a spinner every time
    // they pressed Save, and put them back a frame later. Reading [_loaded]
    // first means the reload happens underneath a form that never flickers.
    if (_loaded case final base?) {
      _seed(base);
      return _form(strings, base);
    }

    return stored.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _withSections(_Centred(text: '$error')),
      data: (fromDb) {
        // Seeded once. Re-seeding on every rebuild would fight the typing,
        // and this rebuilds on each keystroke.
        final base = _loaded = fromDb;
        _seed(base);
        return _form(strings, base);
      },
    );
  }

  Widget _form(AppStrings strings, ReceiptProfile base) {
    final palette = context.pos;
    // Recomputed as the operator types, so the ETA block's warning appears and
    // disappears under their hands rather than only after a save — and so
    // does the slip beside the form.
    final edited = _edited(base);
    // With e-receipts off there is no authority to answer to: the paper's own
    // rules, the registration number as an optional printed line, and none of
    // the filing-only codes.
    final files = ref.watch(etaFilingEnabledProvider);
    final filing = files ? edited.filingProblems : edited.printProblems;
    final problemFor = <String, String>{
      for (final problem in filing) problem.field: problem.message,
    };
    final session = ref.watch(sessionProvider).valueOrNull;

    final form = ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        Text(
          strings.receiptProfileExplain,
          style: PosText.ui(size: 13, color: palette.muted, height: 1.6),
        ),
        const SizedBox(height: PosSpace.xl),

        MicroLabel(strings.receiptProfileOnThePaper),
        const SizedBox(height: PosSpace.md),
        _Field(
          label: strings.receiptTradeName,
          controller: _box(ProfileField.tradeName),
          onChanged: _rebuild,
          problem: problemFor[ProfileField.tradeName],
        ),
        _Field(
          label: strings.receiptPhone,
          controller: _box('phone'),
          onChanged: _rebuild,
          optional: true,
        ),
        _Field(
          label: strings.receiptHeaderNote,
          controller: _box('header_note'),
          onChanged: _rebuild,
          optional: true,
        ),
        _Field(
          label: strings.receiptFooterNote,
          controller: _box('footer_note'),
          onChanged: _rebuild,
          optional: true,
        ),

        const SizedBox(height: PosSpace.xl),
        if (files) ...[
          _EtaBanner(complete: filing.isEmpty, blank: base.isBlank),
          const SizedBox(height: PosSpace.md),
        ],

        _Field(
          label: strings.receiptRegistrationNumber,
          controller: _box(ProfileField.registrationNumber),
          onChanged: _rebuild,
          mono: true,
          optional: !files,
          problem: problemFor[ProfileField.registrationNumber],
        ),
        if (files) ...[
          _Field(
            label: strings.receiptActivityCode,
            controller: _box(ProfileField.activityCode),
            onChanged: _rebuild,
            mono: true,
            problem: problemFor[ProfileField.activityCode],
          ),
          _Field(
            label: strings.receiptBranchCode,
            controller: _box(ProfileField.branchCode),
            onChanged: _rebuild,
            mono: true,
            problem: problemFor[ProfileField.branchCode],
          ),
        ],

        const SizedBox(height: PosSpace.lg),
        MicroLabel(strings.receiptBranchAddress),
        const SizedBox(height: PosSpace.md),
        _Field(
          label: strings.receiptCountry,
          controller: _box(ProfileField.country),
          onChanged: _rebuild,
          mono: true,
          problem: problemFor[ProfileField.country],
        ),
        _Field(
          label: strings.receiptGovernorate,
          controller: _box(ProfileField.governate),
          onChanged: _rebuild,
          problem: problemFor[ProfileField.governate],
        ),
        _Field(
          label: strings.receiptCity,
          controller: _box(ProfileField.regionCity),
          onChanged: _rebuild,
          problem: problemFor[ProfileField.regionCity],
        ),
        _Field(
          label: strings.receiptStreet,
          controller: _box(ProfileField.street),
          onChanged: _rebuild,
          problem: problemFor[ProfileField.street],
        ),
        _Field(
          label: strings.receiptBuildingNumber,
          controller: _box(ProfileField.buildingNumber),
          onChanged: _rebuild,
          problem: problemFor[ProfileField.buildingNumber],
        ),
        _Field(
          label: strings.receiptPostalCode,
          controller: _box('postal_code'),
          onChanged: _rebuild,
          optional: true,
          mono: true,
        ),
        _Field(
          label: strings.receiptFloor,
          controller: _box('floor'),
          onChanged: _rebuild,
          optional: true,
        ),
        _Field(
          label: strings.receiptRoom,
          controller: _box('room'),
          onChanged: _rebuild,
          optional: true,
        ),
        _Field(
          label: strings.receiptLandmark,
          controller: _box('landmark'),
          onChanged: _rebuild,
          optional: true,
        ),

        if (_note != null) ...[
          const SizedBox(height: PosSpace.lg),
          Text(_note!, style: PosText.ui(size: 12.5, color: palette.body)),
        ],
        const SizedBox(height: PosSpace.xl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PosButton(
            key: const Key('receipt-profile-save'),
            label: strings.receiptProfileSave,
            background: palette.ink,
            foreground: palette.onInk,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            onPressed: _busy ? null : () => _save(base),
          ),
        ),
        for (final section in widget.sections) ...[
          const SizedBox(height: PosSpace.s28),
          section,
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: form),
        _Preview(
          paper: ReceiptPaper(
            data: _sample(ref.watch(catalogProvider).valueOrNull),
            profile: edited,
            tenantName: session?.tenantName ?? '',
            terminalCode: session?.terminalCode ?? '',
            cashierName: widget.admin.name,
          ),
        ),
      ],
    );
  }

  /// A sale for the preview, from this restaurant's own menu.
  ///
  /// **Real items, not an invented one.** Two dishes the restaurant sells, at
  /// their prices, taxed the way this till taxes — so the preview is a slip it
  /// could actually print. With no menu to read, the slip shows the profile
  /// and no lines, rather than a dish nobody here has ever sold.
  ReceiptData _sample(Catalog? catalog) {
    var ticket = Ticket(
      id: 'receipt-profile-preview',
      orderType: OrderType.takeaway,
      taxConfig: ref.watch(taxConfigProvider),
    );
    final products = [
      for (final product in catalog?.products ?? const <Product>[])
        if (!product.isOpenPrice) product,
    ].take(2);
    for (final product in products) {
      ticket =
          TicketEngine.addLine(
            ticket,
            product,
            groups: [
              for (final group in catalog!.modifierGroups)
                if (product.modifierGroupIds.contains(group.id)) group,
            ],
          ).ticket ??
          ticket;
    }
    // Settled in cash, so the slip reads as a paid sale rather than one with
    // nothing handed over.
    final cash = TenderMethod.seeded.first;
    ticket =
        TicketEngine.addTender(ticket, typeId: cash.id, label: cash.nameEn)
            .ticket ??
        ticket;
    return ReceiptData.fromTicket(ticket);
  }

  void _rebuild(String _) => setState(() {});

  /// A pane with no form still has General's other sections under it: a till
  /// with no database can still change its language, and the appearance card
  /// is the one that does not need one.
  Widget _withSections(Widget message) => widget.sections.isEmpty
      ? message
      : ListView(
          padding: const EdgeInsets.all(PosSpace.xl),
          children: [
            message,
            for (final section in widget.sections) ...[
              const SizedBox(height: PosSpace.s28),
              section,
            ],
          ],
        );
}

/// Says whether this branch could file a receipt today.
///
/// Its own widget because it is the one line on the pane that answers the
/// question the mandate actually asks, and it has three answers, not two:
/// nothing entered, something missing, ready.
class _EtaBanner extends StatelessWidget {
  const _EtaBanner({required this.complete, required this.blank});

  final bool complete;
  final bool blank;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final (background, ink, text) = switch ((complete, blank)) {
      (true, _) => (palette.okSoft, palette.ok, strings.receiptEtaReady),
      (false, true) => (
        palette.chipBg,
        palette.chipText,
        strings.receiptEtaNotSetUp,
      ),
      (false, false) => (
        palette.warnSoft,
        palette.warn,
        strings.receiptEtaIncomplete,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.receiptProfileForTheAuthority,
            style: PosText.ui(size: 13, weight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: PosText.ui(size: 12.5, color: ink, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// The slip as it will print, beside the form that writes it.
///
/// The paper is white in both themes — `ReceiptPaper` pins its own palette,
/// because paper is white in a dark room too. The desk it lies on is part of
/// this form, though, and follows the theme like the rest of it: the receipt
/// dialogs' fixed desk grey is exempt in `theme_test.dart` only because those
/// files draw nothing but the slip.
class _Preview extends StatelessWidget {
  const _Preview({required this.paper});

  final Widget paper;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      key: const Key('receipt-profile-preview'),
      width: 380,
      decoration: BoxDecoration(
        color: context.pos.chipBg,
        border: BorderDirectional(start: context.pos.hairline),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PosSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MicroLabel(strings.receiptPreviewAction),
            const SizedBox(height: PosSpace.sm),
            paper,
            const SizedBox(height: PosSpace.md),
            Text(
              strings.receiptPreviewNote,
              textAlign: TextAlign.center,
              style: PosText.ui(size: 12, color: context.pos.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.onChanged,
    this.optional = false,
    this.mono = false,
    this.problem,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool optional;

  /// A registration number, an activity code, a postal code. Numbers read in
  /// mono and stay left to right, in Arabic as much as in English.
  final bool mono;

  final String? problem;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      style: mono
          ? PosText.mono(size: 15, color: palette.ink)
          : PosText.ui(size: 15, color: palette.ink),
      textDirection: mono ? TextDirection.ltr : null,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: PosSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(
            optional ? context.strings.optionalField(label) : label,
          ),
          const SizedBox(height: PosSpace.xs),
          SizedBox(width: 420, child: field),
          if (problem != null) ...[
            const SizedBox(height: 4),
            // Under the box it belongs to. A list of complaints at the bottom
            // of a form with fourteen inputs is a list nobody reads twice.
            Text(
              problem!,
              style: PosText.ui(size: 11.5, color: palette.warn),
            ),
          ],
        ],
      ),
    );
  }
}

class _Centred extends StatelessWidget {
  const _Centred({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 13.5, color: context.pos.muted, height: 1.6),
      ),
    ),
  );
}
