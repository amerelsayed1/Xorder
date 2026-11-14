import 'dart:io';

import '../../core/config/printer_config.dart';
import '../../domain/repositories/repositories.dart';
import 'network_printer_ports.dart';
import 'winspool.dart';

/// The printers the operating system has installed, and the bytes to drive
/// them — which at a counter is the USB receipt printer plugged into the till.
///
/// **RAW, not rendered.** A spooler is two things: a page-description layer
/// that turns documents into dots, and a queue that hands bytes to a port.
/// The first has no idea what a cash drawer is; the second does not need to.
/// A job submitted with the `RAW` datatype on Windows, or `-o raw` through
/// CUPS, goes down the cable exactly as given — kick, cut, raster and all —
/// which is how every ESC/POS till on Windows has printed for twenty years.
/// The earlier note here that the spooler "cannot reach the drawer" described
/// the rendering path, and was right about that path only.
///
/// The name the OS gave the printer is the whole identity — `EPSON TM-T20III`
/// — and it is stable across restarts, which the receipt queue relies on.
/// [PrinterConfig.transportOf] is what keeps these names out of the network
/// port's address parser.
///
/// The platform-specific half is [SpoolerBackend], injected so this class can
/// be tested with no spooler at all, and so the two real backends stay as
/// small as their APIs allow.
class SpoolerPrinterPorts implements HardwarePorts {
  const SpoolerPrinterPorts(this.backend);

  /// The spooler this machine has. [SpoolerBackend.forThisPlatform] picks.
  final SpoolerBackend backend;

  /// Printers that exist on every Windows machine and print nothing a
  /// customer can hold. Listing them would put "Microsoft Print to PDF" in
  /// front of an installer as a choice, and — worse — turn a till with one
  /// real printer into a till with three, which is what makes the wizard ask.
  static final _virtual = RegExp(
    r'pdf|xps|onenote|fax|microsoft print|send to|document writer',
    caseSensitive: false,
  );

  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async {
    final List<String> names;
    try {
      names = await backend.installedPrinters();
    } on Object {
      // No spooler, or one that will not answer, is the same as no printer:
      // the network sweep beside this still runs, and the hardware screen
      // still lets somebody type a name.
      return const [];
    }

    final found = [
      for (final name in names)
        if (name.trim().isNotEmpty && !_virtual.hasMatch(name))
          DiscoveredPrinter(
            name: name.trim(),
            transport: PrinterConfig.transportUsb,
          ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return found;
  }

  @override
  Future<bool> testPrint(String printerName) =>
      sendJob(printerName: printerName, bytes: EscPos.testReceipt());

  @override
  Future<bool> sendJob({
    required String printerName,
    required List<int> bytes,
  }) async {
    final name = printerName.trim();
    if (name.isEmpty) return false;
    try {
      return await backend.writeRaw(name, bytes);
    } on Object {
      // Like the network port: a printer that is unplugged is an ordinary
      // Tuesday, the sale is complete, and the receipt queues.
      return false;
    }
  }
}

/// What a spooler has to be able to do for [SpoolerPrinterPorts]: say which
/// printers are installed, and push bytes through one untouched.
abstract interface class SpoolerBackend {
  Future<List<String>> installedPrinters();

  /// True when the spooler accepted the whole job.
  Future<bool> writeRaw(String printerName, List<int> bytes);

  /// Windows gets winspool; macOS and Linux get CUPS; a tablet has no spooler
  /// this build can reach and gets [NoSpooler], which finds nothing.
  static SpoolerBackend forThisPlatform() {
    if (Platform.isWindows) return const WinspoolBackend();
    if (Platform.isMacOS || Platform.isLinux) return const CupsBackend();
    return const NoSpooler();
  }
}

/// A platform with no spooler this build talks to.
class NoSpooler implements SpoolerBackend {
  const NoSpooler();

  @override
  Future<List<String>> installedPrinters() async => const [];

  @override
  Future<bool> writeRaw(String printerName, List<int> bytes) async => false;
}

/// CUPS, through the two commands every macOS and Linux machine has.
///
/// `lpstat -p` lists the printers; `lp -d NAME -o raw` hands the bytes to
/// the named one unrendered. Processes rather than libcups, for the reason
/// `pg_tools.dart` shells out to `pg_dump`: the binding would be ten times
/// the code for exactly two calls.
class CupsBackend implements SpoolerBackend {
  const CupsBackend({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  @override
  Future<List<String>> installedPrinters() async {
    final result = await Process.run('lpstat', const ['-p']).timeout(timeout);
    if (result.exitCode != 0) return const [];
    return parseLpstat(result.stdout as String);
  }

  /// `printer EPSON_TM_T20III is idle.  enabled since …` → `EPSON_TM_T20III`.
  ///
  /// Public and pure so the parser is tested against captured output rather
  /// than against whatever printers the developer's Mac happens to have.
  static List<String> parseLpstat(String output) => [
    for (final line in output.split('\n'))
      if (line.startsWith('printer '))
        line.substring('printer '.length).split(' ').first.trim(),
  ]..removeWhere((name) => name.isEmpty);

  @override
  Future<bool> writeRaw(String printerName, List<int> bytes) async {
    // `-s` silences the "request id is …" line; `-` reads the job from stdin,
    // so the bytes never touch a temporary file.
    final process = await Process.start('lp', [
      '-d',
      printerName,
      '-o',
      'raw',
      '-s',
      '-',
    ]);
    process.stdin.add(bytes);
    await process.stdin.close();
    return await process.exitCode.timeout(timeout) == 0;
  }
}

/// The Windows print spooler, through `winspool.drv`.
///
/// Lives in its own file so the FFI bindings are imported by one unit; the
/// library is opened lazily, so the import costs nothing on a Mac.
class WinspoolBackend implements SpoolerBackend {
  const WinspoolBackend();

  @override
  Future<List<String>> installedPrinters() async => winspoolInstalledPrinters();

  @override
  Future<bool> writeRaw(String printerName, List<int> bytes) async =>
      winspoolWriteRaw(printerName, bytes);
}

/// Every printer this till can reach: the network sweep and the spooler,
/// asked together, and a job routed to whichever one the name belongs to.
///
/// One binding, so nothing above the port has to know there are two ways to
/// reach paper. The routing rule is [PrinterConfig.transportOf], the same
/// rule the settings screen shows beside the name, so what the installer is
/// told and where the bytes go cannot disagree.
class CompositeHardwarePorts implements HardwarePorts {
  const CompositeHardwarePorts({required this.network, required this.spooler});

  final HardwarePorts network;
  final HardwarePorts spooler;

  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async {
    // In parallel: the sweep takes a second, the spooler answers at once, and
    // an installer is watching the button.
    final results = await Future.wait([
      _quietly(spooler.discoverPrinters),
      _quietly(network.discoverPrinters),
    ]);
    return [for (final list in results) ...list];
  }

  /// One side failing must not hide the other's printers.
  Future<List<DiscoveredPrinter>> _quietly(
    Future<List<DiscoveredPrinter>> Function() scan,
  ) async {
    try {
      return await scan();
    } on Object {
      return const [];
    }
  }

  @override
  Future<bool> testPrint(String printerName) =>
      _portFor(printerName).testPrint(printerName);

  @override
  Future<bool> sendJob({
    required String printerName,
    required List<int> bytes,
  }) => _portFor(printerName).sendJob(printerName: printerName, bytes: bytes);

  HardwarePorts _portFor(String name) =>
      PrinterConfig.transportOf(name) == PrinterConfig.transportNetwork
      ? network
      : spooler;
}
