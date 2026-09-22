import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/printer_config.dart';
import 'package:xorder_pos/data/hardware/network_printer_ports.dart';
import 'package:xorder_pos/data/hardware/spooler_printer_ports.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';

/// A spooler in memory: the printers it claims to have, and what it was
/// handed to print.
class _Spooler implements SpoolerBackend {
  _Spooler(this.printers, {this.accepts = true, this.throws = false});

  final List<String> printers;
  final bool accepts;
  final bool throws;
  final jobs = <(String, List<int>)>[];

  @override
  Future<List<String>> installedPrinters() async {
    if (throws) throw StateError('no spooler');
    return printers;
  }

  @override
  Future<bool> writeRaw(String printerName, List<int> bytes) async {
    if (throws) throw StateError('no spooler');
    if (!accepts) return false;
    jobs.add((printerName, bytes));
    return true;
  }
}

/// The network side, recorded rather than swept.
class _Network implements HardwarePorts {
  final jobs = <(String, List<int>)>[];

  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async => const [
    DiscoveredPrinter(name: '192.168.1.44:9100', transport: 'network'),
  ];

  @override
  Future<bool> testPrint(String printerName) async {
    jobs.add((printerName, EscPos.testReceipt()));
    return true;
  }

  @override
  Future<bool> sendJob({
    required String printerName,
    required List<int> bytes,
  }) async {
    jobs.add((printerName, bytes));
    return true;
  }
}

void main() {
  group('which transport a name addresses', () {
    test('an address is the network, with or without a port', () {
      expect(PrinterConfig.transportOf('192.168.1.44:9100'), 'network');
      expect(PrinterConfig.transportOf('192.168.1.44'), 'network');
      expect(PrinterConfig.transportOf('kitchen.local:9100'), 'network');
      expect(PrinterConfig.transportOf(' 10.0.0.5:9101 '), 'network');
    });

    test('the name the OS gave a plugged-in printer is the spooler', () {
      // The shapes a Windows spooler actually produces, including the ones
      // with spaces and hashes that no address parser should ever see.
      expect(PrinterConfig.transportOf('EPSON TM-T20III'), 'usb');
      expect(PrinterConfig.transportOf('POS-80'), 'usb');
      expect(PrinterConfig.transportOf('Receipt'), 'usb');
      expect(PrinterConfig.transportOf('EPSON TM-T20III #2'), 'usb');
    });

    test('and the config reads it off its own name', () {
      expect(const PrinterConfig(name: 'EPSON TM-T20III').transport, 'usb');
      expect(const PrinterConfig(name: '10.0.0.5:9100').transport, 'network');
      // Nothing configured reads as network, which is what every config file
      // written before the spooler existed was.
      expect(PrinterConfig.none.transport, 'network');
    });
  });

  group('the spooler port', () {
    test('lists what is installed, as USB, without the virtual printers', () async {
      final ports = SpoolerPrinterPorts(
        _Spooler([
          'Microsoft Print to PDF',
          'EPSON TM-T20III',
          'Microsoft XPS Document Writer',
          'OneNote (Desktop)',
          'Fax',
          'POS-80',
          '  ',
        ]),
      );

      final found = await ports.discoverPrinters();

      expect([for (final p in found) p.name], ['EPSON TM-T20III', 'POS-80']);
      expect(found.every((p) => p.transport == 'usb'), isTrue);
    });

    test('a spooler that will not answer is no printers, not a crash', () async {
      final ports = SpoolerPrinterPorts(_Spooler(const [], throws: true));
      expect(await ports.discoverPrinters(), isEmpty);
      expect(
        await ports.sendJob(printerName: 'POS-80', bytes: const [1]),
        isFalse,
      );
    });

    test('a test print is the same test receipt the network sends', () async {
      final spooler = _Spooler(const ['POS-80']);
      await SpoolerPrinterPorts(spooler).testPrint('POS-80');

      expect(spooler.jobs.single.$1, 'POS-80');
      expect(spooler.jobs.single.$2, EscPos.testReceipt());
    });

    test('a job goes down untouched, and a refusal is false', () async {
      final spooler = _Spooler(const ['POS-80']);
      final bytes = [...EscPos.initialise, ...EscPos.openDrawer, ...EscPos.cut];

      expect(
        await SpoolerPrinterPorts(spooler).sendJob(printerName: 'POS-80', bytes: bytes),
        isTrue,
      );
      expect(spooler.jobs.single.$2, bytes, reason: 'RAW means these bytes');

      final refusing = _Spooler(const ['POS-80'], accepts: false);
      expect(
        await SpoolerPrinterPorts(refusing).sendJob(printerName: 'POS-80', bytes: bytes),
        isFalse,
      );
      expect(
        await SpoolerPrinterPorts(refusing).sendJob(printerName: '', bytes: bytes),
        isFalse,
      );
    });
  });

  group('lpstat -p', () {
    test('yields the printer names and nothing else', () {
      const output = '''
printer EPSON_TM_T20III is idle.  enabled since Mon 21 Sep 2026 10:14:02 EET
printer Brother_HL_L2350DW disabled since Tue 15 Sep 2026 09:00:00 EET -
	Paused
printer POS_80 is idle.  enabled since Mon 21 Sep 2026 10:14:02 EET
''';
      expect(CupsBackend.parseLpstat(output), [
        'EPSON_TM_T20III',
        'Brother_HL_L2350DW',
        'POS_80',
      ]);
    });

    test('a machine with no printers is an empty list', () {
      expect(CupsBackend.parseLpstat('lpstat: No destinations added.\n'), isEmpty);
      expect(CupsBackend.parseLpstat(''), isEmpty);
    });
  });

  group('the composite', () {
    test('finds both kinds at once', () async {
      final ports = CompositeHardwarePorts(
        network: _Network(),
        spooler: SpoolerPrinterPorts(_Spooler(const ['EPSON TM-T20III'])),
      );

      final found = await ports.discoverPrinters();

      expect({for (final p in found) p.name: p.transport}, {
        'EPSON TM-T20III': 'usb',
        '192.168.1.44:9100': 'network',
      });
    });

    test('routes a job by the shape of the name', () async {
      final network = _Network();
      final spooler = _Spooler(const ['EPSON TM-T20III']);
      final ports = CompositeHardwarePorts(
        network: network,
        spooler: SpoolerPrinterPorts(spooler),
      );

      await ports.sendJob(printerName: '192.168.1.44:9100', bytes: const [1]);
      await ports.sendJob(printerName: 'EPSON TM-T20III', bytes: const [2]);
      await ports.testPrint('EPSON TM-T20III');

      expect(network.jobs.single.$1, '192.168.1.44:9100');
      expect(network.jobs.single.$2, [1]);
      expect(spooler.jobs.map((j) => j.$1), ['EPSON TM-T20III', 'EPSON TM-T20III']);
      expect(spooler.jobs.first.$2, [2]);
    });

    test('one side failing does not hide the other', () async {
      final ports = CompositeHardwarePorts(
        network: _Network(),
        spooler: SpoolerPrinterPorts(_Spooler(const [], throws: true)),
      );

      final found = await ports.discoverPrinters();
      expect(found.map((p) => p.name), ['192.168.1.44:9100']);
    });
  });
}
