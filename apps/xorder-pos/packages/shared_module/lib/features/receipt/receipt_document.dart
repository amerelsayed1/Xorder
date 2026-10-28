/// What the slip **says**, as a list of blocks, before anything decides what it
/// looks like.
///
/// **Why a document rather than more painting code.** The printed receipt is
/// rendered to a bitmap by `ReceiptRaster` and the on-screen one is a widget
/// tree in `receipt_paper.dart`. Both now walk this one list, block by block,
/// with the sizes in `slip_style.dart` — so the preview cannot show a line the
/// paper lacks, or put one in a different place. It also gives a test
/// something to read: asserting "the printed slip carries the invoice number
/// and the total" against a list of blocks is a claim about the receipt, where
/// the same assertion against a bitmap would be optical character recognition.
///
/// The preview used to be its own widget tree, deliberately left alone when
/// printing arrived. That held until the layout changed: the owner's design of
/// 2026-09-13 would have had to be built twice, and the second copy is the one
/// that drifts.
library;

import 'dart:typed_data';

import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/tender_method.dart';
import 'receipt_data.dart';

/// How a centred line is set. Not a font: the renderers pick the actual sizes
/// for the paper, from `SlipMetrics`.
enum SlipEmphasis {
  /// The business's name. Largest words on the paper.
  title,

  /// Ordinary lines — the address, a note.
  body,

  /// Boilerplate and disclosures.
  small,

  /// The thank-you.
  strong,
}

/// Which separator. The design uses all three to say how far apart two blocks
/// are: dashed inside the money, heavy above the total, solid everywhere else.
enum SlipRuleWeight { solid, dashed, heavy }

/// The pictures on the slip. Drawn by `paintSlipGlyph`, never an icon font.
enum SlipGlyph { phone, pin }

sealed class SlipBlock {
  const SlipBlock();
}

/// A centred line of text, optionally led by a glyph.
class SlipCentre extends SlipBlock {
  const SlipCentre(
    this.text, {
    this.emphasis = SlipEmphasis.body,
    this.glyph,
    this.numeric = false,
  });

  final String text;
  final SlipEmphasis emphasis;
  final SlipGlyph? glyph;

  /// A phone number or a registration number: mono, and left to right even
  /// on an Arabic slip.
  final bool numeric;
}

/// The business's logo, as the till holds it (a PNG or JPEG), centred at the
/// top of the slip.
///
/// The bytes, not a decoded picture: a document is data that tests read, and
/// decoding is the renderers' job — each decodes for its own surface, and a
/// logo that will not decode is skipped by both, never an error (XORD-024).
class SlipLogo extends SlipBlock {
  const SlipLogo(this.bytes);

  final Uint8List bytes;
}

/// A boxed banner: REPRINT, REFUNDED. Boxed because it has to survive being
/// photographed and photocopied.
class SlipStamp extends SlipBlock {
  const SlipStamp(this.text);

  final String text;
}

/// A label on the reading side and a value on the other.
///
/// A [numeric] value is set LTR in Latin digits even on an Arabic slip — the
/// house rule for every number in the product, and on a receipt it is also
/// what makes the paper checkable by somebody who does not read Arabic. A
/// value that is words — a cashier's name, an order type — reads in the slip's
/// own direction instead, or an Arabic name would be laid out backwards.
class SlipRow extends SlipBlock {
  const SlipRow(
    this.label,
    this.value, {
    this.struck = false,
    this.numeric = true,
    this.amount = false,
    this.secondary = false,
  });

  final String label;
  final String value;
  final bool struck;
  final bool numeric;

  /// The label is the quieter half: a fact about the sale (date, cashier) set
  /// beside its value, not money. Drawn at `SlipMetrics.bodySecondary`, so the
  /// value reads first.
  final bool secondary;

  /// The value is money, with its currency code. Amounts share one width on
  /// the slip and end at the same edge, so their decimal points stand in one
  /// line — on an Arabic slip too, where a left-aligned figure would line up
  /// its first digit instead (XORD-025).
  final bool amount;
}

class SlipRule extends SlipBlock {
  const SlipRule([this.weight = SlipRuleWeight.solid]);

  final SlipRuleWeight weight;
}

class SlipGap extends SlipBlock {
  const SlipGap([this.dots = 8]);

  /// Between two blocks of one section that are not separated by a rule. Equal
  /// to `SlipMetrics.spaceMd`; a test holds the two together (this file cannot
  /// import the sizes, which import this).
  const SlipGap.medium() : dots = 12;

  /// Between two sections that have no rule between them. Equal to
  /// `SlipMetrics.spaceSection`.
  const SlipGap.section() : dots = 20;

  final int dots;
}

/// The QR square Egypt requires on the customer's copy. Only ever emitted when
/// there is a payload — see [ReceiptData.etaQrPayload].
class SlipQr extends SlipBlock {
  const SlipQr(this.payload);

  final String payload;
}

/// The shaded heading of the items table.
class SlipItemsHeader extends SlipBlock {
  const SlipItemsHeader(this.item, this.quantity, this.price);

  final String item;
  final String quantity;
  final String price;
}

/// One row of the items table.
///
/// [price] is the **line** total — what this row adds to the subtotal — not
/// the unit price. On two of a dish the column shows what two cost, so the
/// column sums to the subtotal printed under it.
class SlipItem extends SlipBlock {
  const SlipItem(this.name, this.quantity, this.price, {this.struck = false});

  final String name;
  final String quantity;
  final String price;

  /// A voided line stays on the slip, struck through, because the kitchen made
  /// it and the customer watched it happen.
  final bool struck;
}

/// The TOTAL: the label large, the figure larger, the currency under it.
class SlipGrandTotal extends SlipBlock {
  const SlipGrandTotal(this.label, this.amount, this.currency);

  final String label;
  final String amount;
  final String currency;
}

/// A rate in basis points as the paper prints it: 1400 is "14", 1250 is
/// "12.5", 1225 is "12.25".
///
/// Integer arithmetic, deliberately. This was `(bp / 100).toStringAsFixed(0)`,
/// which is a double next to a tax rate and printed a 12.5% rate as "13%" — a
/// figure on a customer's receipt that the tax on the line beside it does not
/// match.
String receiptPercent(int bp) {
  final whole = bp ~/ 100;
  final hundredths = bp % 100;
  if (hundredths == 0) return '$whole';
  if (hundredths % 10 == 0) return '$whole.${hundredths ~/ 10}';
  return '$whole.${hundredths.toString().padLeft(2, '0')}';
}

/// The slip, in the language the till is set to.
class ReceiptDocument {
  const ReceiptDocument({required this.blocks, required this.rightToLeft});

  final List<SlipBlock> blocks;

  /// Which way the paper reads. Set from the strings, not from the customer:
  /// the till prints in the language it is configured in.
  final bool rightToLeft;

  /// Build the slip from what was sold.
  ///
  /// The same arguments `ReceiptPaper` takes, and in the same order, so the
  /// call sites can hand both the identical values. [logo] is the business's
  /// picture, or null for none. [tenderMethods] is the
  /// till's configured list, used only to put a tender's Arabic name on an
  /// Arabic slip.
  factory ReceiptDocument.of(
    ReceiptData data, {
    required AppStrings strings,
    required String tenantName,
    required String terminalCode,
    required String cashierName,
    ReceiptProfile profile = const ReceiptProfile(branchId: 0),
    List<TenderMethod> tenderMethods = TenderMethod.seeded,
    Uint8List? logo,
  }) {
    final blocks = <SlipBlock>[];

    // ── Header ────────────────────────────────────────────────────────────
    //
    // The stamps come before the business's name, not after the total:
    // somebody handed a slip has to know what it is before they read what is
    // on it.
    if (data.isReprint) blocks.add(SlipStamp(strings.receiptReprintMark));
    if (data.wasRefunded) {
      blocks.add(
        SlipStamp(
          strings.receiptRefundedMark(data.refunded.format(withCurrency: true)),
        ),
      );
    }

    // The business's own logo, above its name, when it has one and the till
    // is set to print it (the caller passes null otherwise). Nothing of
    // XOrder's goes up here: the mark is the footer's, at the bottom.
    if (logo != null && logo.isNotEmpty) blocks.add(SlipLogo(logo));
    final name = profile.tradeName.trim().isEmpty
        ? tenantName
        : profile.tradeName;
    blocks.add(SlipCentre(name.toUpperCase(), emphasis: SlipEmphasis.title));

    // Phone, address and registration print only when somebody has entered
    // them. This header used to read `TAX REG 000-000-000` unconditionally — a
    // fabricated registration number on a document an inspector may read.
    final phone = (profile.phone ?? '').trim();
    if (phone.isNotEmpty) {
      blocks.add(SlipCentre(phone, glyph: SlipGlyph.phone, numeric: true));
    }
    if (profile.address.printed.isNotEmpty) {
      blocks.add(SlipCentre(profile.address.printed, glyph: SlipGlyph.pin));
    }
    final registration = profile.registrationNumber.trim();
    if (registration.isNotEmpty) {
      blocks.add(
        SlipCentre(
          strings.taxRegistrationLine(registration),
          emphasis: SlipEmphasis.small,
          numeric: true,
        ),
      );
    }
    final header = (profile.headerNote ?? '').trim();
    if (header.isNotEmpty) {
      blocks.add(SlipCentre(header, emphasis: SlipEmphasis.small));
    }

    // ── Who, when, which ──────────────────────────────────────────────────
    blocks.add(const SlipRule());
    blocks.add(
      SlipRow(strings.receiptDate, _date(data.occurredAt), secondary: true),
    );
    blocks.add(
      SlipRow(strings.receiptTime, _time(data.occurredAt), secondary: true),
    );
    blocks.add(
      data.invoiceNumber == null
          // No number yet: the platform assigns it. PROVISIONAL is what stops
          // this paper being taken for a numbered invoice.
          ? SlipRow(
              strings.receiptOrderNumber,
              strings.provisionalInvoice,
              numeric: false,
              secondary: true,
            )
          : SlipRow(
              strings.receiptOrderNumber,
              data.invoiceNumber!,
              secondary: true,
            ),
    );
    // The number the cashier calls out. Beside the invoice number, which stays
    // the legal one; absent for an order outside any trading day.
    if (data.dayOrderNumber case final number?) {
      blocks.add(
        SlipRow(strings.receiptDayOrderNumber, '$number', secondary: true),
      );
    }
    blocks.add(
      SlipRow(
        strings.receiptCashier,
        cashierName.toUpperCase(),
        numeric: false,
        secondary: true,
      ),
    );
    if (terminalCode.trim().isNotEmpty) {
      blocks.add(
        SlipRow(
          strings.receiptTerminal,
          terminalCode.trim(),
          secondary: true,
        ),
      );
    }
    blocks.add(
      SlipRow(
        strings.receiptOrderType,
        [
          data.orderType.label(strings),
          if (data.tableLabel != null) data.tableLabel!,
        ].join(' · '),
        numeric: false,
        secondary: true,
      ),
    );

    // ── What was sold ─────────────────────────────────────────────────────
    //
    // Space, not a rule: the shaded heading of the table is the line.
    blocks.add(const SlipGap.medium());
    blocks.add(
      SlipItemsHeader(
        strings.receiptItem,
        strings.receiptQty,
        strings.receiptPrice,
      ),
    );
    for (final line in data.lines) {
      blocks.add(
        SlipItem(
          '${line.name}${line.wasRepriced ? ' *' : ''}',
          '${line.quantity}',
          line.lineTotal.format(withCurrency: true),
          struck: line.isVoided,
        ),
      );
    }

    // ── Money ─────────────────────────────────────────────────────────────
    //
    // Every figure below is one the engine or the ledger produced. This
    // builder formats them and chooses labels; it adds, subtracts and rounds
    // nothing. The owner's mockup added its discount instead of taking it off
    // and printed a total 28.72 too high — the arithmetic is the one part of
    // that picture this slip does not copy.
    blocks.add(const SlipRule(SlipRuleWeight.dashed));
    blocks.add(
      SlipRow(
        strings.receiptSubtotal,
        data.subtotal.format(withCurrency: true),
        amount: true,
      ),
    );
    if (!data.discount.isZero) {
      blocks.add(
        SlipRow(
          switch (data.discountBp) {
            final bp? => strings.receiptDiscount(receiptPercent(bp)),
            null => strings.orderDetailDiscount,
          },
          '-${data.discount.format(withCurrency: true)}',
          amount: true,
        ),
      );
    }
    if (!data.service.isZero) {
      blocks.add(
        SlipRow(
          switch (data.serviceBp) {
            final bp? => strings.receiptService(receiptPercent(bp)),
            null => strings.orderDetailService,
          },
          data.service.format(withCurrency: true),
          amount: true,
        ),
      );
    }
    // One line per rate when the breakdown accounts for the whole figure —
    // a zero-rated bottle of water beside a standard-rated meal is two lines —
    // and the bare word otherwise. See `ReceiptData.taxLines`.
    if (data.taxLines.isEmpty) {
      blocks.add(
        SlipRow(
          strings.orderDetailVat,
          data.vat.format(withCurrency: true),
          amount: true,
        ),
      );
    } else {
      for (final line in data.taxLines) {
        blocks.add(
          SlipRow(
            strings.receiptVat(receiptPercent(line.rateBp)),
            line.amount.format(withCurrency: true),
            amount: true,
          ),
        );
      }
    }
    blocks.add(const SlipRule(SlipRuleWeight.heavy));
    blocks.add(
      SlipGrandTotal(
        strings.receiptTotal,
        data.total.format(),
        data.total.currency,
      ),
    );

    // ── How it was paid ───────────────────────────────────────────────────
    //
    // Space under the heavy rule and the total, not a second rule.
    blocks.add(const SlipGap.section());
    final payments = data.payments;
    if (payments.length == 1) {
      blocks.add(
        SlipRow(
          strings.receiptPaymentMethod,
          _tenderName(payments.single, strings, tenderMethods),
          numeric: false,
        ),
      );
    } else if (payments.length > 1) {
      // A split bill: one line per tender, so the card slip in the customer's
      // other hand matches a line on this one.
      blocks.add(SlipRow(strings.receiptPaymentMethod, '', numeric: false));
      for (final payment in payments) {
        blocks.add(
          SlipRow(
            _tenderName(payment, strings, tenderMethods),
            payment.amount.format(withCurrency: true),
            amount: true,
          ),
        );
      }
    }
    blocks.add(
      SlipRow(
        strings.receiptPaid,
        data.paid.format(withCurrency: true),
        amount: true,
      ),
    );
    if (!data.change.isZero) {
      blocks.add(
        SlipRow(
          strings.receiptChange,
          data.change.format(withCurrency: true),
          amount: true,
        ),
      );
    }
    blocks.add(const SlipGap.section());

    // ── Footer ────────────────────────────────────────────────────────────
    //
    // Nothing at all about sync on an offline till: it has no platform to be
    // synced with, and printing either answer would be a claim about a
    // relationship that does not exist.
    if (data.syncNote != ReceiptSyncNote.none) {
      blocks.add(
        SlipCentre(
          data.syncNote == ReceiptSyncNote.queued
              ? strings.receiptQueuedOffline
              : strings.receiptSynced,
          emphasis: SlipEmphasis.small,
        ),
      );
    }

    // Below the money, above the thank-you: where a customer looks when they
    // have been told to scan something.
    if (data.etaQrPayload case final payload?) {
      blocks.add(const SlipGap());
      blocks.add(SlipQr(payload));
      blocks.add(const SlipGap());
    }

    // The business's own words — a wifi password, an offer, an opening time
    // — before the boilerplate thank-you, which reads as the sign-off.
    final footer = (profile.footerNote ?? '').trim();
    if (footer.isNotEmpty) blocks.add(SlipCentre(footer));

    // One thank-you (owner, 26 Oct 2026): it was a thank-you, a second line
    // saying the same and a heart. The business's own words stay above it.
    blocks.add(
      SlipCentre(strings.receiptThanks, emphasis: SlipEmphasis.strong),
    );
    blocks.add(const SlipCentre('xorder.io', emphasis: SlipEmphasis.small));

    // Tax figures came from read-only device config rather than the server.
    // Disclosing that is deliberate — see POS-BE-013.
    if (data.taxFromDeviceConfig) {
      blocks.add(
        SlipCentre(strings.receiptTaxFromDevice, emphasis: SlipEmphasis.small),
      );
    }

    return ReceiptDocument(
      blocks: blocks,
      rightToLeft: strings.languageCode == 'ar',
    );
  }

  /// What to call a tender on this slip.
  ///
  /// The stored label is English on purpose — see `TenderMethod.wireLabel`. An
  /// Arabic slip shows the method's Arabic name, but **only while the method
  /// still carries the name the payment was taken under**. A method renamed
  /// since would otherwise have a reprint call last month's payment by this
  /// month's name, which is a small rewrite of what the customer paid with.
  static String _tenderName(
    ReceiptPayment payment,
    AppStrings strings,
    List<TenderMethod> methods,
  ) {
    final id = payment.tenderTypeId;
    if (id == null || strings.languageCode != 'ar') return payment.label;
    for (final method in methods) {
      if (method.id == id && method.nameEn == payment.label) {
        return method.displayName(strings.languageCode);
      }
    }
    return payment.label;
  }

  /// With the year. It used to be day and month only, on the view that a
  /// receipt is read within a minute of the sale; the owner's design prints
  /// it, and a slip reprinted next year for an accountant needs it.
  static String _date(DateTime at) =>
      '${_two(at.day)}/${_two(at.month)}/${at.year}';

  static String _time(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
