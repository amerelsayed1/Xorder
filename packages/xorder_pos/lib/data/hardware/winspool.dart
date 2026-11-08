import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// The two `winspool.drv` calls the till makes, and nothing else.
///
/// Both are synchronous Win32 calls behind an async face, because a
/// `WritePrinter` of a receipt-sized job returns in milliseconds — the spooler
/// takes the bytes and the cable drains them — and an isolate for that would
/// be ceremony.
///
/// Everything allocated here is freed in a `finally`. The `win32` package is
/// only ever *called* on Windows; on a Mac this file is imported and never
/// reached, and `DynamicLibrary.open` is lazy, so the import costs nothing.

/// The names of every printer installed locally or connected from a server.
///
/// `PRINTER_INFO_4` is the cheap level: name and attributes, no round trip to
/// the driver. Two calls, as the API demands — the first says how many bytes,
/// the second fills them.
List<String> winspoolInstalledPrinters() {
  const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  final needed = calloc<Uint32>();
  final returned = calloc<Uint32>();
  Pointer<Uint8> buffer = nullptr;
  try {
    EnumPrinters(flags, null, 4, null, 0, needed, returned);
    final size = needed.value;
    if (size == 0) return const [];

    buffer = calloc<Uint8>(size);
    final ok = EnumPrinters(flags, null, 4, buffer, size, needed, returned);
    if (!ok.value) return const [];

    final entries = buffer.cast<PRINTER_INFO_4>();
    return [
      for (var i = 0; i < returned.value; i++)
        (entries + i).ref.pPrinterName.toDartString(),
    ];
  } finally {
    if (buffer != nullptr) calloc.free(buffer);
    calloc.free(needed);
    calloc.free(returned);
  }
}

/// Hand [bytes] to the named printer with the `RAW` datatype: no rendering,
/// no code page, the job exactly as built.
bool winspoolWriteRaw(String printerName, List<int> bytes) {
  final name = printerName.toNativeUtf16();
  final handle = calloc<Pointer>();
  try {
    if (!OpenPrinter(PCWSTR(name), handle, null).value) return false;
    final printer = PRINTER_HANDLE(handle.value);
    try {
      final doc = calloc<DOC_INFO_1>();
      final docName = 'XOrder POS receipt'.toNativeUtf16();
      final datatype = 'RAW'.toNativeUtf16();
      try {
        doc.ref
          ..pDocName = PWSTR(docName)
          ..pOutputFile = PWSTR(nullptr)
          ..pDatatype = PWSTR(datatype);
        if (StartDocPrinter(printer, 1, doc) == 0) return false;
        try {
          if (!StartPagePrinter(printer)) return false;
          try {
            final buffer = calloc<Uint8>(bytes.length);
            final written = calloc<Uint32>();
            try {
              buffer.asTypedList(bytes.length).setAll(0, bytes);
              return WritePrinter(printer, buffer, bytes.length, written) &&
                  written.value == bytes.length;
            } finally {
              calloc.free(buffer);
              calloc.free(written);
            }
          } finally {
            EndPagePrinter(printer);
          }
        } finally {
          EndDocPrinter(printer);
        }
      } finally {
        calloc.free(doc);
        calloc.free(docName);
        calloc.free(datatype);
      }
    } finally {
      ClosePrinter(printer);
    }
  } finally {
    calloc.free(handle);
    calloc.free(name);
  }
}
