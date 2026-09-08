import 'package:flutter/material.dart';

import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../domain/models/receipt_profile.dart';
import 'receipt_data.dart';
import 'receipt_qr.dart';

/// A receipt is paper, and paper is white in a dark room too.
///
/// This renders a PRINTED artefact rather than a screen: white stock, black
/// impact ink. Theming it would put the dark theme's near-white ink on white
/// stock and hand the operator a blank preview of a receipt that will print
/// perfectly well.
const receiptPalette = PosPalette.light;

/// The slip itself.
///
/// Extracted from `ReceiptDialog` when reprint arrived: a settled order is not
/// a `Ticket`, and rebuilding one from the ledger would re-price the sale
/// against today's menu. Both paths now hand this the same [ReceiptData], which
/// holds no catalogue and no tax configuration — so there is nothing here that
/// *could* recompute a total.
class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({
    super.key,
    required this.data,
    required this.tenantName,
    required this.terminalCode,
    required this.cashierName,
    this.profile = const ReceiptProfile(branchId: 0),
  });

  final ReceiptData data;

  /// Who this branch is, as Management entered it.
  ///
  /// Defaults to a blank profile so a till that has never been set up still
  /// prints — it just prints less. Every line below that reads this is
  /// conditional for exactly that reason.
  final ReceiptProfile profile;

  /// The tenant as the session knows it. Still here because it is what a till
  /// has before anybody opens Management, and [ReceiptProfile.tradeName] wins
  /// once somebody has.
  final String tenantName;
  final String terminalCode;
  final String cashierName;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.s18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Before the restaurant's name, not after the total. Somebody handed
          // a slip has to know what it is before they read what is on it —
          // §18's "the REPRINT marking on the output" is about a document that
          // cannot be passed off as an original.
          if (data.isReprint) _stamp(strings.receiptReprintMark, receiptPalette.warn),
          if (data.wasRefunded)
            _stamp(
              strings.receiptRefundedMark(data.refunded.format()),
              receiptPalette.danger,
            ),
          Text(
            (profile.tradeName.trim().isEmpty
                    ? tenantName
                    : profile.tradeName)
                .toUpperCase(),
            textAlign: TextAlign.center,
            style: PosText.ui(
              size: 17,
              weight: FontWeight.w800,
              color: receiptPalette.ink,
            ),
          ),
          // Address, phone and registration number print only when somebody
          // has entered them.
          //
          // This line used to read `TAX REG 000-000-000` unconditionally — a
          // fabricated registration number on a document a customer keeps and
          // an inspector may read. A blank space is not a compliance problem;
          // a made-up number is.
          if (profile.address.printed.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              profile.address.printed,
              textAlign: TextAlign.center,
              style: PosText.ui(size: 11, color: receiptPalette.body),
            ),
          ],
          if ((profile.phone ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                profile.phone!.trim(),
                textAlign: TextAlign.center,
                style: PosText.mono(size: 11, color: receiptPalette.body),
              ),
            ),
          ],
          if (profile.registrationNumber.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                strings.taxRegistrationLine(profile.registrationNumber.trim()),
                textAlign: TextAlign.center,
                style: PosText.mono(size: 11, color: receiptPalette.body),
              ),
            ),
          ],
          if ((profile.headerNote ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.headerNote!.trim(),
              textAlign: TextAlign.center,
              style: PosText.ui(size: 11, color: receiptPalette.body),
            ),
          ],
          _dashed(),
          _row(
            data.invoiceNumber ?? strings.provisionalInvoice,
            '$terminalCode / ${cashierName.toUpperCase()}',
          ),
          _row(
            [
              data.orderType.label(strings),
              if (data.tableLabel != null) data.tableLabel!,
            ].join(' · '),
            _timestamp(data.occurredAt),
          ),
          _dashed(),
          for (final line in data.lines) _line(strings, line),
          _dashed(),
          _row(strings.receiptSubtotal, data.subtotal.format(), size: 12),
          if (!data.discount.isZero)
            _row(
              strings.orderDetailDiscount,
              '-${data.discount.format()}',
              size: 12,
            ),
          if (!data.service.isZero)
            _row(
              // The rate when it is known, the bare word when it is not. See
              // `ReceiptData.fromOrder` for why a reprint has no rate.
              data.serviceBp == null
                  ? strings.orderDetailService
                  : strings.receiptService(
                      (data.serviceBp! / 100).toStringAsFixed(0),
                    ),
              data.service.format(),
              size: 12,
            ),
          _row(
            data.vatBp == null
                ? strings.orderDetailVat
                : strings.receiptVat((data.vatBp! / 100).toStringAsFixed(0)),
            data.vat.format(),
            size: 12,
          ),
          Container(
            margin: const EdgeInsets.only(top: PosSpace.sm),
            padding: const EdgeInsets.only(top: PosSpace.sm),
            decoration: BoxDecoration(
              border: Border(top: receiptPalette.emphasis),
            ),
            child: Row(
              children: [
                Text(
                  strings.receiptTotal,
                  style: PosText.mono(
                    color: receiptPalette.inkWarm,
                    size: 17,
                    weight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  data.total.format(),
                  style: PosText.mono(
                    color: receiptPalette.inkWarm,
                    size: 17,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _row(strings.receiptPaid, data.paid.format(), size: 12),
          if (!data.change.isZero)
            _row(strings.receiptChange, data.change.format(), size: 12),
          _dashed(),
          // Nothing at all on an offline till. It has no platform to be
          // synced with, and printing either answer would be a claim about a
          // relationship that does not exist.
          if (data.syncNote != ReceiptSyncNote.none)
            Text(
              data.syncNote == ReceiptSyncNote.queued
                  ? strings.receiptQueuedOffline
                  : strings.receiptSynced,
              textAlign: TextAlign.center,
              style: PosText.mono(size: 10.5, color: receiptPalette.body),
            ),
          // Above the boilerplate, below the totals: where a customer looks
          // when they have been told to scan something.
          if (data.etaQrPayload case final payload?) ...[
            const SizedBox(height: PosSpace.sm),
            Center(child: ReceiptQr(payload: payload)),
            const SizedBox(height: PosSpace.sm),
          ],
          Text(
            'xorder.io',
            textAlign: TextAlign.center,
            style: PosText.mono(size: 10.5, color: receiptPalette.body),
          ),
          // The restaurant's own words, above the boilerplate thanks — a
          // wifi password, an offer, an opening time.
          if ((profile.footerNote ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                profile.footerNote!.trim(),
                textAlign: TextAlign.center,
                style: PosText.ui(size: 11, color: receiptPalette.body),
              ),
            ),
          Text(
            strings.receiptThanks,
            textAlign: TextAlign.center,
            style: strings.languageCode == 'ar'
                ? PosText.arabic(size: 11, color: receiptPalette.body)
                : PosText.mono(size: 10.5, color: receiptPalette.body),
          ),
          // Tax figures came from read-only device config, not the server.
          // Disclosing that is deliberate — see POS-BE-013.
          if (data.taxFromDeviceConfig)
            Padding(
              padding: const EdgeInsets.only(top: PosSpace.sm),
              child: Text(
                strings.receiptTaxFromDevice,
                textAlign: TextAlign.center,
                style: PosText.mono(size: 9.5, color: receiptPalette.warn),
              ),
            ),
        ],
      ),
    );
  }

  /// A banner across the top of the slip. Boxed and centred, because it has to
  /// survive being photographed, faxed and photocopied.
  Widget _stamp(String text, Color colour) => Container(
    margin: const EdgeInsets.only(bottom: PosSpace.sm),
    padding: const EdgeInsets.symmetric(vertical: 3),
    decoration: BoxDecoration(border: Border.all(color: colour, width: 2)),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: PosText.mono(size: 13, weight: FontWeight.w800, color: colour),
    ),
  );

  Widget _line(AppStrings strings, ReceiptLine line) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${line.quantity} ${line.name}'
            '${line.wasRepriced ? ' *' : ''}',
            overflow: TextOverflow.ellipsis,
            style:
                PosText.mono(
                  size: 12.5,
                  color: line.isVoided
                      ? receiptPalette.muted
                      : receiptPalette.ink,
                ).copyWith(
                  decoration: line.isVoided ? TextDecoration.lineThrough : null,
                ),
          ),
        ),
        Text(
          line.lineTotal.format(),
          style:
              PosText.mono(
                size: 12.5,
                color: line.isVoided
                    ? receiptPalette.muted
                    : receiptPalette.ink,
              ).copyWith(
                decoration: line.isVoided ? TextDecoration.lineThrough : null,
              ),
        ),
      ],
    ),
  );

  static String _timestamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
  }

  Widget _dashed() => Padding(
    padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
    child: Text(
      '-' * 42,
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: PosText.mono(size: 11, color: receiptPalette.shellLineMeta),
    ),
  );

  Widget _row(String left, String right, {double size = 12.5}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Expanded(
          child: Text(
            left,
            overflow: TextOverflow.ellipsis,
            style: PosText.mono(size: size, color: receiptPalette.ink),
          ),
        ),
        Text(
          right,
          style: PosText.mono(size: size, color: receiptPalette.ink),
        ),
      ],
    ),
  );
}
