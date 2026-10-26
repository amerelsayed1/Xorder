/// Which printer this till prints on, and how wide its paper is.
///
/// A property of the **terminal**, like the branch and the language: the
/// printer is bolted to this counter, and a cashier signing in does not bring
/// one with them. So it is saved beside them in `config.json` rather than in
/// the branch database — a till that cannot reach PostgreSQL still has to be
/// able to print the slip it is holding.
class PrinterConfig {
  const PrinterConfig({
    this.name,
    this.paperWidthDots = width80mm,
    this.printLogo = true,
  });

  /// Nothing configured. What a till has before anybody has run the wizard's
  /// hardware step, and what a till with no printer keeps for ever.
  static const none = PrinterConfig();

  /// 80mm paper, 203dpi, 72mm printable — the roll every Egyptian restaurant
  /// buys, and the default for that reason.
  static const width80mm = 576;

  /// 58mm paper. Common on the small hand-held printers a delivery rider
  /// carries, and on a few counter-top units.
  static const width58mm = 384;

  /// `192.168.1.44:9100` for a printer on the network, or the name the
  /// operating system gives a plugged-in one — `EPSON TM-T20III` — as the
  /// wizard's scan found it. Null when nothing is set up.
  ///
  /// The name is the whole identity: it is what the receipt queue keys a
  /// job on, so it has to be stable across restarts, and it is what decides
  /// which transport a job goes down — see [transportOf].
  final String? name;

  /// `network` or `usb`, read off the shape of [name].
  ///
  /// Not a stored field, on purpose. The transport was being displayed by
  /// the scan and dropped by everything that saved the choice, and a second
  /// field that had to be kept in step with the name at every one of those
  /// places would be one more thing to forget. The name is enough: a
  /// printer on the network is written down as an address, a printer the
  /// operating system installed is written down as the name it gave it, and
  /// the two shapes do not overlap in practice.
  String get transport => transportOf(name ?? '');

  /// The transport a printer [name] addresses.
  ///
  /// An IPv4 address, with or without a port, or anything ending in
  /// `:port`, is the network. Everything else — `EPSON TM-T20III`,
  /// `POS-80`, `Receipt` — is a printer the OS spooler knows, which at a
  /// counter means the one plugged into the till. A bare hostname is read as
  /// a spooler name; whoever types a network printer by hostname types the
  /// port with it, as the field's hint shows.
  static String transportOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return transportNetwork;
    if (_ipv4.hasMatch(trimmed) || _hostAndPort.hasMatch(trimmed)) {
      return transportNetwork;
    }
    return transportUsb;
  }

  static const transportNetwork = 'network';
  static const transportUsb = 'usb';

  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d{1,5})?$');
  static final _hostAndPort = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]*:\d{1,5}$');

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

  /// Whether the restaurant's logo is printed (and previewed) at the top of the
  /// receipt, when it has one (XORD-024).
  ///
  /// On by default: a till that already holds a logo prints it after the
  /// update, and an owner who would rather save the roll turns it off here.
  /// A property of the till like the paper width, because the paper is the
  /// till's, so it lives in the config file and not in the branch database.
  final bool printLogo;

  /// True when there is somewhere to send bytes.
  bool get isConfigured => (name?.trim().isNotEmpty ?? false);

  PrinterConfig copyWith({
    String? name,
    int? paperWidthDots,
    bool? printLogo,
  }) => PrinterConfig(
    name: name ?? this.name,
    paperWidthDots: paperWidthDots ?? this.paperWidthDots,
    printLogo: printLogo ?? this.printLogo,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'paper_width_dots': paperWidthDots,
    'print_logo': printLogo,
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
      // Absent, or anything but a plain false, reads as on: a file written by a
      // build that did not know the key must not switch the logo off.
      printLogo: json['print_logo'] != false,
    );
  }
}
