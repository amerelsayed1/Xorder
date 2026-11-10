/// What tax a line attracts, and the breakdown a filing needs.
///
/// **Why this exists.** The ticket used to carry one VAT rate for the whole
/// bill — `TaxConfig.vatBp` — which cannot express a zero-rated bottle of water
/// beside a standard-rated meal, and a business selling food *and* packaged
/// goods has both. It also cannot produce the per-rate breakdown Egypt's ETA
/// e-receipt requires, which is the harder problem: a receipt that states one
/// VAT figure and no rates behind it is not filable.
library;

import '../../core/money/money.dart';

/// A rate, named, as the business's accountant knows it.
class TaxGroup {
  const TaxGroup({
    required this.id,
    required this.nameEn,
    required this.rateBp,
    this.nameAr,
    this.isDefault = false,
    this.isActive = true,
    this.etaTaxType = EtaTaxCode.valueAdded,
    String? etaSubType,
    // A private field cannot be a public named parameter, and the name has to
    // be public because callers set it.
    // ignore: prefer_initializing_formals
  }) : _etaSubType = etaSubType;

  /// The rate every product falls back to when it names none.
  ///
  /// 14% is Egypt's standard rate. It is a *fallback*, not an assumption: a
  /// business that configures its groups gets what it configured, and one
  /// that has not gets what it was already being charged before this existed.
  static const standard = TaxGroup(
    id: 0,
    nameEn: 'VAT',
    nameAr: 'ضريبة القيمة المضافة',
    rateBp: 1400,
    isDefault: true,
  );

  final int id;
  final String nameEn;
  final String? nameAr;

  /// Basis points. 1400 = 14%, 0 = zero-rated.
  final int rateBp;

  final bool isDefault;

  /// Retired rather than deleted: a product points at this row, and removing it
  /// would silently reclassify that product onto the fallback rate.
  ///
  /// **Deliberately not part of [operator ==].** The till only ever sees active
  /// groups — the provider filters them — so this cannot vary among the keys the
  /// ticket accumulates by, and adding a field to that equality is how the
  /// rounding-once-per-rate property gets broken by accident.
  final bool isActive;

  /// How Egypt's tax authority names this tax, and which of its sub-rates this
  /// is. Carried on the group rather than derived from [rateBp], because two
  /// taxes can share a rate and mean different things to a filing — and
  /// because ETA reissue these codes, so a table mapping 14% to a constant
  /// would be wrong the first time they did.
  ///
  /// Defaults are Egypt's standard VAT, which is what a business selling
  /// food charges. See [EtaTaxCode].
  final String etaTaxType;

  final String? _etaSubType;

  /// The sub-rate code, falling back on the rate when nobody has set one.
  ///
  /// The fallback has to look at [rateBp] rather than being a plain default:
  /// a zero-rated group filed under the standard code would be a filing that
  /// says the business charged 14% and collected nothing, which is the
  /// discrepancy an audit exists to find. Set it explicitly for anything
  /// beyond these two — exempt, reduced, and the rest of ETA's list.
  String get etaSubType =>
      _etaSubType ??
      (rateBp == 0 ? EtaTaxCode.zeroRated : EtaTaxCode.standardVat);

  /// Zero-rated and exempt look the same on a total and are different on a
  /// filing. Both are `rateBp == 0` here; which one it is belongs to the group's
  /// name, because that is what an accountant reconciles against.
  bool get isZeroRated => rateBp == 0;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// Value equality, and it is load-bearing rather than a nicety.
  ///
  /// The ticket accumulates tax bases in a `Map<TaxGroup, Money>` so that each
  /// rate is rounded once. `TaxConfig.defaultTaxGroup` builds its fallback
  /// fresh on every call, so without this every line became its own key and was
  /// rounded alone — 3.33 at 14% three times is 1.41, where 9.99 taxed once is
  /// 1.40. The golden money tests written before Wave A caught it on the first
  /// run, which is exactly what they are for.
  @override
  bool operator ==(Object other) =>
      other is TaxGroup &&
      other.id == id &&
      other.rateBp == rateBp &&
      other.nameEn == nameEn &&
      other.etaTaxType == etaTaxType &&
      other.etaSubType == etaSubType;

  @override
  int get hashCode => Object.hash(id, rateBp, nameEn, etaTaxType, etaSubType);
}

/// One rate's worth of tax on one order.
///
/// This is the `tax_lines[]` the risk register promised in v1 and nobody built.
/// One entry per **rate**, not per line: tax is filed by rate, and rounding once
/// per rate is what keeps a ticket's arithmetic identical to what it was when
/// every product shared one.
/// The codes Egypt's tax authority files a tax under.
///
/// Only the two a business actually charges are named. The rest of ETA's
/// list — stamp duty, table tax, entertainment — belongs to industries this
/// product does not serve, and naming codes nobody has checked would be worse
/// than not naming them.
abstract final class EtaTaxCode {
  /// `T1`, value added tax.
  static const valueAdded = 'T1';

  /// `V009`, the standard VAT rate.
  static const standardVat = 'V009';

  /// `V003`, zero-rated.
  static const zeroRated = 'V003';
}

class TaxLine {
  const TaxLine({
    required this.name,
    required this.rateBp,
    required this.base,
    required this.amount,
    this.taxGroupId,
    this.etaTaxType = EtaTaxCode.valueAdded,
    String? etaSubType,
    // A private field cannot be a public named parameter, and the name has to
    // be public because callers set it.
    // ignore: prefer_initializing_formals
  }) : _etaSubType = etaSubType;

  final String name;
  final int rateBp;

  /// What the rate was applied to.
  final Money base;

  final Money amount;
  final int? taxGroupId;

  /// Copied from the [TaxGroup] this line came out of, not looked up. A line
  /// on a settled order has to keep saying what it was filed as even after
  /// somebody edits the group it came from.
  final String etaTaxType;

  final String? _etaSubType;

  /// See [TaxGroup.etaSubType] — the same fallback, for the same reason.
  String get etaSubType =>
      _etaSubType ??
      (rateBp == 0 ? EtaTaxCode.zeroRated : EtaTaxCode.standardVat);
}

/// How a set of lines is taxed.
///
/// **Rounded once per rate, not once per line.** Three lines of 33.33 at 14%
/// round to 4.67 each and sum to 14.01; the same 99.99 taxed once rounds to
/// 14.00. Filing is by rate, so per-rate is both correct and — on a menu where
/// everything shares one rate — arithmetically identical to the single-rate
/// calculation this replaces. Every golden money test written for Wave A still
/// passes unchanged, which is how that claim is checked rather than asserted.
abstract final class TaxEngine {
  /// [bases] maps a tax group to what it is charged on.
  ///
  /// Groups with a zero base are dropped: a receipt listing "0% on 0.00" tells
  /// nobody anything. A zero-rated group with a real base is **kept**, because
  /// "40.00 at 0%" is exactly what a filing needs to see.
  /// [inclusive] is whether the amounts in [bases] already contain the tax
  /// (§37, §85).
  ///
  /// The two are different arithmetic, not a presentation choice: 114.00
  /// holding 14% contains 14.00, where 114.00 plus 14% is 129.96. What the
  /// filing then wants is the **net** base either way, so an inclusive line
  /// reports `gross − tax` as its base rather than the gross it was priced at.
  static List<TaxLine> linesFor(
    Map<TaxGroup, Money> bases, {
    bool inclusive = false,
  }) {
    final lines = <TaxLine>[];

    for (final entry in bases.entries) {
      final group = entry.key;
      final base = entry.value;
      if (base.minor <= 0) continue;

      final amount = inclusive
          ? base.taxWithinBp(group.rateBp)
          : base.percentBp(group.rateBp);

      lines.add(
        TaxLine(
          name: group.nameEn,
          rateBp: group.rateBp,
          base: inclusive ? base - amount : base,
          amount: amount,
          taxGroupId: group.id,
          etaTaxType: group.etaTaxType,
          etaSubType: group.etaSubType,
        ),
      );
    }

    // Highest rate first, so the standard rate leads and the exceptions read as
    // exceptions. Stable on the id for two groups sharing a rate.
    lines.sort((a, b) {
      final byRate = b.rateBp.compareTo(a.rateBp);
      return byRate != 0 ? byRate : (a.taxGroupId ?? 0).compareTo(b.taxGroupId ?? 0);
    });
    return lines;
  }

  static Money totalOf(List<TaxLine> lines, {Money zero = Money.zero}) =>
      lines.fold(zero, (sum, line) => sum + line.amount);

  /// A refund's tax, split across the rates its sale was taxed at, in minor
  /// units — one figure per entry of [saleAmounts], in the same order.
  ///
  /// **The one place a refund's tax is given a rate.** A refund row carries
  /// its VAT as one figure (`pos_refunds.vat_minor`); the sale carries it by
  /// rate (`pos_order_taxes`). Both the ETA credit note and the Finance tab's
  /// taxes need the refund by rate, and two copies of this arithmetic would be
  /// a credit note and a tax report that disagree by a piastre about the same
  /// refund — the discrepancy an accountant finds on the one day it matters.
  ///
  /// Each rate but the last takes its share of [refundVat] in proportion to
  /// what it was on the sale, floored; the last takes what is left, so the
  /// parts always sum to exactly [refundVat]. The order is the caller's, and
  /// both callers read `pos_order_taxes` by `id`. Largest remainder was the
  /// alternative, and would move a piastre between rates on credit notes
  /// already queued for filing under this rule.
  ///
  /// A sale that recorded no VAT gives every rate but the last nothing: a
  /// proportion of zero is not a proportion.
  static List<int> refundShares({
    required List<int> saleAmounts,
    required int saleVat,
    required int refundVat,
  }) {
    if (saleAmounts.isEmpty) return const [];
    var left = refundVat;
    return [
      for (var i = 0; i < saleAmounts.length; i++)
        () {
          final share = i == saleAmounts.length - 1
              ? left
              : saleVat == 0
              ? 0
              : saleAmounts[i] * refundVat ~/ saleVat;
          left -= share;
          return share;
        }(),
    ];
  }
}
