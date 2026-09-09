/// Which printer this till prints on, and how wide its paper is.
///
/// A property of the **terminal**, like the branch and the language: the
/// printer is bolted to this counter, and a cashier signing in does not bring
/// one with them. So it is saved beside them in `config.json` rather than in
/// the branch database — a till that cannot reach PostgreSQL still has to be
/// able to print the slip it is holding.
class PrinterConfig {
  const PrinterConfig({this.name, this.paperWidthDots = width80mm});

  /// Nothing configured. What a till has before anybody has run the wizard's
  /// hardware step, and what a till with no printer keeps for ever.
  static const none = PrinterConfig();

  /// 80mm paper, 203dpi, 72mm printable — the roll every Egyptian restaurant
  /// buys, and the default for that reason.
  static const width80mm = 576;

  /// 58mm paper. Common on the small hand-held printers a delivery rider
  /// carries, and on a few counter-top units.
  static const width58mm = 384;

  /// `192.168.1.44` or `192.168.1.44:9100`, as the wizard's scan found it.
  /// Null when nothing is set up.
  final String? name;

  /// The width of the printable area **in dots**, which is what the raster is
  /// built to.
  ///
  /// This has to be right, and it has to be visible to whoever installs the
  /// till, because a printer given a raster wider than its head does not scale
  /// it — it prints the left-hand dots it has room for and throws the rest
  /// away. Set 576 on a 58mm printer and the customer gets a receipt with the
  /// totals column missing, which reads as a broken till rather than as a
  /// mis-set number.
  ///
  /// Dots rather than millimetres deliberately: the printer counts in dots,
  /// and converting mm→dots here would need the head's dpi, which is a second
  /// number nobody standing at a counter knows.
  final int paperWidthDots;

  /// True when there is somewhere to send bytes.
  bool get isConfigured => (name?.trim().isNotEmpty ?? false);

  PrinterConfig copyWith({String? name, int? paperWidthDots}) => PrinterConfig(
    name: name ?? this.name,
    paperWidthDots: paperWidthDots ?? this.paperWidthDots,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'paper_width_dots': paperWidthDots,
  };

  /// Tolerant, like every other reader of the config file: a terminal must boot
  /// holding a file written by a build that knew one field more or less. An
  /// absent or nonsensical width reads as 80mm, which is the roll the till is
  /// most likely to have on it — and the installer can see and change it.
  static PrinterConfig fromJson(Map<String, Object?> json) {
    final width = (json['paper_width_dots'] as num?)?.toInt();
    return PrinterConfig(
      name: json['name'] as String?,
      paperWidthDots: width == null || width < 128 || width > 2048
          ? width80mm
          : width,
    );
  }
}
