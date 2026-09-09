/// What the slip **says**, as a list of blocks, before anything decides what it
/// looks like.
///
/// **Why a document rather than more painting code.** The printed receipt is
/// rendered to a bitmap by [ReceiptRaster] and the on-screen one is a widget
/// tree in `receipt_paper.dart`; splitting the *wording* out means the two
/// cannot end up disagreeing about which lines a receipt has, only about how
/// they are drawn. It also gives a test something to read: asserting "the
/// printed slip carries the invoice number and the total" against a list of
/// blocks is a claim about the receipt, where the same assertion against a
/// bitmap would be optical character recognition.
///
/// The widget was deliberately **not** rewritten to consume this. It is the
/// preview, it lives inside a themed dialog, and rebuilding it against the
/// blocks would be a redesign of a screen that works in a change about
/// printing. What stops them drifting is that both are built from one
/// [ReceiptData] and neither can recompute a figure.
library;

import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/models/receipt_profile.dart';
import 'receipt_data.dart';

/// How a block is set. Not a font: the raster picks the actual sizes for the
/// paper it is printing on, and a 58mm roll cannot use an 80mm roll's.
enum SlipEmphasis {
  /// The restaurant's name. Largest thing on the paper.
  title,

  /// Ordinary lines — items, totals, the address.
  body,

  /// Boilerplate and disclosures.
  small,

  /// The TOTAL, and the boxed stamps above the name.
  strong,
}

sealed class SlipBlock {
  const SlipBlock();
}

/// A centred line of text.
class SlipCentre extends SlipBlock {
  const SlipCentre(this.text, {this.emphasis = SlipEmphasis.body});

  final String text;
  final SlipEmphasis emphasis;
}

/// A boxed banner: REPRINT, REFUNDED. Boxed because it has to survive being
/// photographed and photocopied.
class SlipStamp extends SlipBlock {
  const SlipStamp(this.text);

  final String text;
}

/// A label on one side and a figure on the other.
///
/// [amount] is set LTR in Latin digits even on an Arabic slip — the house rule
/// for every number in the product, and on a receipt it is also what makes the
/// paper checkable by somebody who does not read Arabic.
class SlipRow extends SlipBlock {
  const SlipRow(
    this.label,
    this.amount, {
    this.emphasis = SlipEmphasis.body,
    this.struck = false,
  });

  final String label;
  final String amount;
  final SlipEmphasis emphasis;

  /// A voided line stays on the slip, struck through, because the kitchen made
  /// it and the customer watched it happen.
  final bool struck;
}

/// The dashed separator.
class SlipRule extends SlipBlock {
  const SlipRule();
}

class SlipGap extends SlipBlock {
  const SlipGap([this.dots = 8]);

  final int dots;
}

/// The QR square Egypt requires on the customer's copy. Only ever emitted when
/// there is a payload — see [ReceiptData.etaQrPayload].
class SlipQr extends SlipBlock {
  const SlipQr(this.payload);

  final String payload;
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
  /// The same arguments `ReceiptPaper` takes, and in the same order, so the two
  /// call sites in `receipt_dialog.dart` and `reprint_dialog.dart` can hand
  /// both the identical values.
  factory ReceiptDocument.of(
    ReceiptData data, {
    required AppStrings strings,
    required String tenantName,
    required String terminalCode,
    required String cashierName,
    ReceiptProfile profile = const ReceiptProfile(branchId: 0),
  }) {
    final blocks = <SlipBlock>[];

    // Before the restaurant's name, not after the total: somebody handed a slip
    // has to know what it is before they read what is on it.
    if (data.isReprint) blocks.add(SlipStamp(strings.receiptReprintMark));
    if (data.wasRefunded) {
      blocks.add(SlipStamp(strings.receiptRefundedMark(data.refunded.format())));
    }

    final name = profile.tradeName.trim().isEmpty
        ? tenantName
        : profile.tradeName;
    blocks.add(SlipCentre(name.toUpperCase(), emphasis: SlipEmphasis.title));

    // Address, phone and registration print only when somebody has entered
    // them. This line used to read `TAX REG 000-000-000` unconditionally — a
    // fabricated registration number on a document an inspector may read.
    if (profile.address.printed.isNotEmpty) {
      blocks.add(SlipCentre(profile.address.printed));
    }
    final phone = (profile.phone ?? '').trim();
    if (phone.isNotEmpty) blocks.add(SlipCentre(phone));

    final registration = profile.registrationNumber.trim();
    if (registration.isNotEmpty) {
      blocks.add(SlipCentre(strings.taxRegistrationLine(registration)));
    }
    final header = (profile.headerNote ?? '').trim();
    if (header.isNotEmpty) blocks.add(SlipCentre(header));

    blocks.add(const SlipRule());
    blocks.add(
      SlipRow(
        data.invoiceNumber ?? strings.provisionalInvoice,
        '$terminalCode / ${cashierName.toUpperCase()}',
      ),
    );
    blocks.add(
      SlipRow(
        [
          data.orderType.label(strings),
          if (data.tableLabel != null) data.tableLabel!,
        ].join(' · '),
        _timestamp(data.occurredAt),
      ),
    );
    blocks.add(const SlipRule());

    for (final line in data.lines) {
      blocks.add(
        SlipRow(
          '${line.quantity} ${line.name}${line.wasRepriced ? ' *' : ''}',
          line.lineTotal.format(),
          struck: line.isVoided,
        ),
      );
    }

    blocks.add(const SlipRule());
    blocks.add(SlipRow(strings.receiptSubtotal, data.subtotal.format()));
    if (!data.discount.isZero) {
      blocks.add(
        SlipRow(strings.orderDetailDiscount, '-${data.discount.format()}'),
      );
    }
    if (!data.service.isZero) {
      blocks.add(
        SlipRow(
          // The rate when it is known, the bare word when it is not. A reprint
          // has no rate — see `ReceiptData.fromOrder`.
          data.serviceBp == null
              ? strings.orderDetailService
              : strings.receiptService((data.serviceBp! / 100).toStringAsFixed(0)),
          data.service.format(),
        ),
      );
    }
    blocks.add(
      SlipRow(
        data.vatBp == null
            ? strings.orderDetailVat
            : strings.receiptVat((data.vatBp! / 100).toStringAsFixed(0)),
        data.vat.format(),
      ),
    );
    blocks.add(const SlipGap(4));
    blocks.add(
      SlipRow(
        strings.receiptTotal,
        data.total.format(),
        emphasis: SlipEmphasis.strong,
      ),
    );
    blocks.add(SlipRow(strings.receiptPaid, data.paid.format()));
    if (!data.change.isZero) {
      blocks.add(SlipRow(strings.receiptChange, data.change.format()));
    }
    blocks.add(const SlipRule());

    // Nothing at all on an offline till: it has no platform to be synced with,
    // and printing either answer would be a claim about a relationship that
    // does not exist.
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

    // Above the boilerplate, below the totals: where a customer looks when they
    // have been told to scan something.
    if (data.etaQrPayload case final payload?) {
      blocks.add(const SlipGap());
      blocks.add(SlipQr(payload));
      blocks.add(const SlipGap());
    }

    blocks.add(const SlipCentre('xorder.io', emphasis: SlipEmphasis.small));

    final footer = (profile.footerNote ?? '').trim();
    if (footer.isNotEmpty) blocks.add(SlipCentre(footer));

    blocks.add(SlipCentre(strings.receiptThanks));

    // Tax figures came from read-only device config rather than the server.
    // Disclosing that is deliberate — see POS-BE-013.
    if (data.taxFromDeviceConfig) {
      blocks.add(const SlipGap());
      blocks.add(
        SlipCentre(strings.receiptTaxFromDevice, emphasis: SlipEmphasis.small),
      );
    }

    return ReceiptDocument(
      blocks: blocks,
      rightToLeft: strings.languageCode == 'ar',
    );
  }

  /// Day and time only. A receipt is handed over within a minute of the sale
  /// and the year on it is noise; a reprint carries the invoice number, which
  /// is what anybody looking one up actually searches on.
  static String _timestamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
  }
}
