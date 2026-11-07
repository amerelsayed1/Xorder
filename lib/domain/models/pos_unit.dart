import '../../core/money/quantity.dart';

/// A unit the business counts and buys stock in — kg, litre, box, tray.
///
/// **A name for a code, not a conversion.** A kilogram here is never 1000
/// grams: the till does no unit arithmetic at all (see
/// `core/money/quantity.dart`), so a unit is how a quantity is labelled and
/// nothing more. What it adds over the code is what a person reads — in both
/// languages — and what the tax authority is told the item was sold in.
class PosUnit {
  const PosUnit({
    required this.id,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.etaUnitType = defaultEtaUnitType,
    this.allowsFraction = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int id;

  /// What a purchase line and a stock row store. Fixed once saved: a line
  /// written against "tray" must still read as a tray after somebody renames
  /// it.
  final String code;
  final String nameEn;
  final String? nameAr;

  /// What a unit is filed as until somebody says otherwise: one of something.
  static const defaultEtaUnitType = 'EA';

  /// The tax authority's unit code for this unit — `EA`, `KGM`, `LTR`.
  final String etaUnitType;

  /// Whether half of one is a real amount. 12.5 kg is; 12.5 boxes is not.
  final bool allowsFraction;

  /// Retired rather than deleted: last month's purchase order still names it.
  final bool isActive;
  final int sortOrder;

  QuantityUnit get unit => QuantityUnit(code);

  String displayName(String languageCode) =>
      languageCode == 'ar' && (nameAr?.trim().isNotEmpty ?? false)
      ? nameAr!.trim()
      : nameEn;

  /// Lowercase letters, digits and underscores, starting with a letter — the
  /// same shape the database checks.
  static final codePattern = RegExp(r'^[a-z][a-z0-9_]{0,15}$');

  static final etaPattern = RegExp(r'^[A-Z0-9]{1,6}$');

  PosUnit copyWith({
    int? id,
    String? nameEn,
    String? nameAr,
    String? etaUnitType,
    bool? allowsFraction,
    bool? isActive,
  }) => PosUnit(
    id: id ?? this.id,
    code: code,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    etaUnitType: etaUnitType ?? this.etaUnitType,
    allowsFraction: allowsFraction ?? this.allowsFraction,
    isActive: isActive ?? this.isActive,
    sortOrder: sortOrder,
  );
}
