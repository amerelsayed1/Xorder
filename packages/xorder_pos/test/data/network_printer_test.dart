import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/hardware/network_printer_ports.dart';

/// Network printing, against a real socket.
///
/// A thermal printer on port 9100 is a socket that accepts bytes and never
/// replies, which is exactly what `ServerSocket` on loopback is — so everything
/// here is verifiable without hardware on the desk. What it cannot prove is
/// that a real printer *interprets* the bytes correctly; that needs a printer,
/// and is why the commands are separated from the transport.
void main() {
  group('sending to a printer', () {
    late ServerSocket printer;
    late List<int> received;

    setUp(() async {
      received = [];
      printer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      printer.listen((socket) {
        socket.listen(received.addAll, onDone: socket.destroy);
      });
    });

    tearDown(() => printer.close());

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 150));

    test('a test print reaches the printer as ESC/POS bytes', () async {
      const ports = NetworkPrinterPorts();

      final ok = await ports.testPrint('${printer.address.address}:${printer.port}');
      await settle();

      expect(ok, isTrue);
      expect(received, isNotEmpty);

      // Every job starts with a reset, because the previous job may have left
      // the printer bold or upside down.
      expect(received.take(2), EscPos.initialise);

      // And ends with a cut, or the next receipt prints onto this one.
      expect(received.skip(received.length - EscPos.cut.length), EscPos.cut);
      expect(
        received.join(','),
        contains(EscPos.openDrawer.join(',')),
        reason: 'the test print proves the drawer too — that is half of what an '
            'installer is checking',
      );
      expect(String.fromCharCodes(received), contains('XORDER POS'));
    });

    test('a printer written down without a port still works', () async {
      // Configurable port, so a printer noted as a bare address uses it.
      final ports = NetworkPrinterPorts(port: printer.port);

      expect(await ports.testPrint(printer.address.address), isTrue);
      await settle();
      expect(received, isNotEmpty);
    });

    test('nothing is sent to an address that is not a printer', () async {
      const ports = NetworkPrinterPorts(printTimeout: Duration(milliseconds: 300));

      // Port 1 on loopback: nothing listens, and the connection is refused
      // immediately rather than hanging.
      expect(await ports.testPrint('127.0.0.1:1'), isFalse);
    });

    test('an empty or malformed printer name is refused, not thrown', () async {
      const ports = NetworkPrinterPorts(printTimeout: Duration(milliseconds: 300));

      // A failed test print must never abort setup, so every path returns a
      // boolean rather than raising.
      expect(await ports.testPrint(''), isFalse);
      expect(await ports.testPrint('   '), isFalse);
    });
  });

  group('discovery', () {
    test('finds a listening socket on the local subnet', () async {
      final printer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(printer.close);

      // Present loopback as though it were the till's LAN interface, so the
      // sweep covers 127.0.0.x and finds the socket above.
      final ports = NetworkPrinterPorts(
        port: printer.port,
        probeTimeout: const Duration(milliseconds: 200),
        interfaces: ({bool includeLoopback = false, InternetAddressType? type}) async =>
            NetworkInterface.list(includeLoopback: true, type: InternetAddressType.IPv4),
      );

      final found = await ports.discoverPrinters();

      expect(
        found.map((p) => p.name),
        contains('127.0.0.1:${printer.port}'),
      );
      expect(found.first.transport, 'network');
    });

    test('an empty network yields an empty list, not an error', () async {
      // Port 1 is not something anything listens on, so the whole sweep misses.
      const ports = NetworkPrinterPorts(
        port: 1,
        probeTimeout: Duration(milliseconds: 50),
      );

      // A till with no printer is a valid till. Discovery finding nothing is an
      // ordinary answer, and the wizard must be able to continue past it.
      expect(await ports.discoverPrinters(), isEmpty);
    });
  });

  group('the ESC/POS commands themselves', () {
    test('a cut is partial, so the receipt does not fall on the floor', () {
      expect(EscPos.cut, [0x1D, 0x56, 0x42, 0x00]);
    });

    test('the drawer kick uses timings a solenoid survives', () {
      // 2ms units: 0x25 on, 0xFA off. Too short and it does not throw; too long
      // and it cooks.
      expect(EscPos.openDrawer, [0x1B, 0x70, 0x00, 0x25, 0xFA]);
    });

    test('characters the printer cannot render become "?" rather than nonsense', () {
      // Arabic needs a code page thermal printers disagree about, so this
      // refuses to print confident mojibake onto a customer's receipt.
      final bytes = EscPos.text('Kofta كفتة');

      expect(String.fromCharCodes(bytes.take(6)), 'Kofta ');
      expect(bytes.skip(6), everyElement(0x3F));
    });

    test('a feed cannot overflow the single byte it is sent in', () {
      expect(EscPos.feed(300).last, 255);
      expect(EscPos.feed(-1).last, 0);
    });
  });
}
