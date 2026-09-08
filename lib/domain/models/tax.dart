/// What tax a line attracts, and the breakdown a filing needs.
///
/// **Why this exists.** The ticket used to carry one VAT rate for the whole
/// bill — `TaxConfig.vatBp` — which cannot express a zero-rated bottle of water
/// beside a standard-rated meal, and a restaurant selling food *and* packaged
/// goods has both. It also cannot produce the per-rate breakdown Egypt's ETA
/// e-receipt requires, which is the harder problem: a receipt that states one
/// VAT figure and no rates behind it is not filable.
library;

import '../../core/money/money.dart';

/// A rate, named, as the restaurant's accountant knows it.
class TaxGroup {
  const TaxGroup({
    required this.id,
    required this.nameEn,
    required this.rateBp,
    this.nameAr,
    this.isDefault = false,
  });

  /// The rate every product falls back to when it names none.
  ///
  /// 14% is Egypt's standard rate. It is a *fallback*, not an assumption: a
  /// restaurant that configures its groups gets what it configured, and one
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
      other.nameEn == nameEn;

  @override
  int get hashCode => Object.hash(id, rateBp, nameEn);
}

/// One rate's worth of tax on one order.
///
/// This is the `tax_lines[]` the risk register promised in v1 and nobody built.
/// One entry per **rate**, not per line: tax is filed by rate, and rounding once
/// per rate is what keeps a ticket's arithmetic identical to what it was when
/// every product shared one.
class TaxLine {
  const TaxLine({
    required this.name,
    required this.rateBp,
    required this.base,
    required this.amount,
    this.taxGroupId,
  });

  final String name;
  final int rateBp;

  /// What the rate was applied to.
  final Money base;

  final Money amount;
  final int? taxGroupId;
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
  static List<TaxLine> linesFor(Map<TaxGroup, Money> bases) {
    final lines = <TaxLine>[];

    for (final entry in bases.entries) {
      final group = entry.key;
      final base = entry.value;
      if (base.minor <= 0) continue;

      lines.add(
        TaxLine(
          name: group.nameEn,
          rateBp: group.rateBp,
          base: base,
          amount: base.percentBp(group.rateBp),
          taxGroupId: group.id,
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
}
