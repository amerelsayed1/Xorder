import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/repositories/repositories.dart';

/// Receipt printers reachable over the network, and the bytes to drive them.
///
/// Pure Dart over TCP 9100 — the "RAW" port every ESC/POS thermal printer
/// listens on. No platform channel, so it behaves identically on Windows and
/// macOS and can be tested against a plain socket rather than a printer on
/// somebody's desk.
///
/// This is deliberately **not** the OS print spooler. A receipt printer driven
/// through CUPS or winspool goes through a page-description layer that has no
/// idea what a cash drawer is or where to cut the paper; talking to it directly
/// is both simpler and the only way to reach the drawer kick.
///
/// USB printers are not covered. They need a platform channel per OS, and
/// nothing here pretends otherwise — [discoverPrinters] returns what is on the
/// network and says nothing about what is plugged in.
class NetworkPrinterPorts implements HardwarePorts {
  const NetworkPrinterPorts({
    this.port = 9100,
    this.probeTimeout = const Duration(milliseconds: 300),
    this.printTimeout = const Duration(seconds: 5),
    this.interfaces = NetworkInterface.list,
  });

  /// The RAW/JetDirect port. Configurable because a few printers are set to
  /// 9101/9102 for their second and third ports.
  final int port;

  /// Per-host, not for the whole sweep. A LAN probe that has not answered in a
  /// third of a second is not a printer anyone is waiting for.
  final Duration probeTimeout;

  final Duration printTimeout;

  /// Injected so a test can present a known interface list.
  final Future<List<NetworkInterface>> Function({
    bool includeLoopback,
    InternetAddressType type,
  })
  interfaces;

  /// Sweep this machine's own /24s for anything listening on [port].
  ///
  /// Only /24 — 254 probes per interface, which finishes in about a second in
  /// parallel. Restaurant LANs are /24 essentially without exception, and
  /// sweeping a /16 would be 65,000 connections for a printer that is not there.
  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async {
    final found = <DiscoveredPrinter>[];

    for (final subnet in await _subnets()) {
      final probes = <Future<String?>>[
        for (var host = 1; host < 255; host++) _probe('$subnet.$host'),
      ];

      for (final address in await Future.wait(probes)) {
        if (address != null) {
          found.add(
            DiscoveredPrinter(name: '$address:$port', transport: 'network'),
          );
        }
      }
    }

    found.sort((a, b) => a.name.compareTo(b.name));
    return found;
  }

  /// Print a test receipt.
  ///
  /// Returns false rather than throwing on every failure path: a printer that
  /// is off, unplugged or at a stale address is an ordinary Tuesday, and a
  /// failed test print must never abort setup or a sale. The receipt queues and
  /// the UI says so.
  @override
  Future<bool> testPrint(String printerName) async {
    final target = _parse(printerName);
    if (target == null) return false;

    return send(host: target.$1, port: target.$2, bytes: EscPos.testReceipt());
  }

  @override
  Future<bool> sendJob({
    required String printerName,
    required List<int> bytes,
  }) async {
    final target = _parse(printerName);
    if (target == null) return false;

    return send(host: target.$1, port: target.$2, bytes: bytes);
  }

  /// Write raw bytes to a printer and flush.
  ///
  /// Public because the receipt path needs it too, and because "send these
  /// exact bytes to this printer" is the whole of what this class does.
  Future<bool> send({
    required String host,
    required int port,
    required List<int> bytes,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: printTimeout);
      socket.add(bytes);
      await socket.flush();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      // Destroy rather than close: a thermal printer often never half-closes,
      // and awaiting a graceful shutdown would hang the till behind a receipt.
      socket?.destroy();
    }
  }

  Future<String?> _probe(String address) async {
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: probeTimeout);
      return address;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// The `a.b.c` prefixes of this machine's IPv4 addresses.
  Future<List<String>> _subnets() async {
    final list = await interfaces(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    return {
      for (final interface in list)
        for (final address in interface.addresses)
          address.address.split('.').take(3).join('.'),
    }.toList();
  }

  /// `192.168.1.44:9100` → `('192.168.1.44', 9100)`. A bare address uses the
  /// configured port, so a printer written down without one still works.
  (String, int)? _parse(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final colon = trimmed.lastIndexOf(':');
    if (colon < 0) return (trimmed, port);

    final parsed = int.tryParse(trimmed.substring(colon + 1));
    if (parsed == null) return (trimmed, port);
    return (trimmed.substring(0, colon), parsed);
  }
}

/// ESC/POS command bytes.
///
/// Only the handful a receipt needs. Kept separate from the transport so the
/// bytes are testable without a socket, and so the same commands can be sent
/// over USB when that transport exists.
abstract final class EscPos {
  static const _esc = 0x1B;
  static const _gs = 0x1D;

  /// `ESC @` — reset. Sent first on every job, because the previous job may
  /// have left the printer bold, upside down, or in a code page nobody chose.
  static const initialise = [_esc, 0x40];

  static const alignLeft = [_esc, 0x61, 0x00];
  static const alignCentre = [_esc, 0x61, 0x01];

  static const boldOn = [_esc, 0x45, 0x01];
  static const boldOff = [_esc, 0x45, 0x00];

  /// `GS V 66 0` — feed and partial cut, leaving a tab the customer tears off.
  /// A full cut drops the receipt on the floor.
  static const cut = [_gs, 0x56, 0x42, 0x00];

  /// `ESC p 0 25 250` — kick the drawer on pin 2.
  ///
  /// The two timings are in 2ms units: energise for 50ms, rest for 500ms. Too
  /// short and the solenoid does not throw; too long and it cooks.
  static const openDrawer = [_esc, 0x70, 0x00, 0x25, 0xFA];

  static List<int> feed(int lines) => [_esc, 0x64, lines.clamp(0, 255)];

  /// `GS v 0` — print a raster bit image.
  ///
  /// **This is how a receipt gets printed, and `text` is not.** See
  /// [ReceiptRaster] for the argument: Arabic through a printer code page is a
  /// guess about firmware nobody controls, and the ETA QR has to reach paper
  /// regardless. The whole slip goes down as dots.
  ///
  /// [bits] is one bit per dot, MSB first, each row padded to a whole byte —
  /// exactly the order this command wants, so nothing is repacked here.
  ///
  /// **Sent in bands.** The command accepts a height up to 65535, and plenty of
  /// printers accept it and then run out of image buffer half way down and
  /// print the rest as noise — 4KB of buffer is common on the cheap units this
  /// is aimed at. 128 rows of 80mm paper is 9KB... so bands are sized by bytes
  /// rather than by rows, which is the number the buffer actually cares about.
  static List<int> raster({
    required int width,
    required int height,
    required List<int> bits,
  }) {
    final rowBytes = (width + 7) ~/ 8;
    if (rowBytes == 0 || height == 0) return const [];

    // ~3KB a band, rounded down to whole rows. Small enough for the meanest
    // buffer, large enough that an 80mm receipt is a handful of commands.
    final bandRows = (3072 ~/ rowBytes).clamp(1, 255);

    final out = <int>[];
    for (var top = 0; top < height; top += bandRows) {
      final rows = top + bandRows > height ? height - top : bandRows;
      out.addAll([
        _gs, 0x76, 0x30, 0x00, // GS v 0, mode 0 (normal density)
        rowBytes & 0xFF, (rowBytes >> 8) & 0xFF,
        rows & 0xFF, (rows >> 8) & 0xFF,
      ]);
      out.addAll(bits.sublist(top * rowBytes, (top + rows) * rowBytes));
    }
    return out;
  }

  /// Latin-1, which covers the English side of a receipt.
  ///
  /// Arabic needs a code page the printer actually has loaded, and thermal
  /// printers disagree wildly about which that is — so Arabic receipt printing
  /// is not attempted here rather than printing confident mojibake.
  ///
  /// **This is now only the test print.** A customer's receipt does not come
  /// through here at all: it is rendered to a bitmap and sent with [raster],
  /// which is how the Arabic this comment gave up on reaches paper. What is
  /// left is the installer's slip, which is deliberately English — an installer
  /// checking that a printer is reachable needs eight ASCII words, not a
  /// picture.
  static List<int> text(String value) => Uint8List.fromList(
    value.codeUnits.map((c) => c <= 0xFF ? c : 0x3F).toList(),
  );

  static List<int> line(String value) => [...text(value), 0x0A];

  /// What *Test print* sends. Deliberately proves the three things an installer
  /// needs to know: that it prints, that it cuts, and that the drawer opens.
  static List<int> testReceipt() => [
    ...initialise,
    ...alignCentre,
    ...boldOn,
    ...line('XORDER POS'),
    ...boldOff,
    ...line('Test receipt'),
    ...alignLeft,
    ...line(''),
    ...line('If you can read this, the printer is'),
    ...line('reachable and the paper is loaded.'),
    ...line(''),
    ...line('The drawer should have opened too.'),
    ...feed(3),
    ...openDrawer,
    ...cut,
  ];
}
