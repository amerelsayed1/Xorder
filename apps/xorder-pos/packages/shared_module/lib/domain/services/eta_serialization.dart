/// Turning a receipt into the exact bytes Egypt's tax authority hashes.
///
/// **One tree, two renderings.** The document is built once as an ordered
/// tree and rendered twice — as canonical text to be hashed and signed, and as
/// JSON to be submitted. Building those separately is the classic way to get
/// this wrong: the two drift by one field or one ordering and every signature
/// is rejected, with an error that says nothing about which half is stale. Here
/// they cannot drift, because there is only one thing to change.
///
/// The algorithm is ETA's, from their published serialization approach:
///
/// * every property name is emitted uppercased and in double quotes;
/// * every simple value is emitted **verbatim** and in double quotes — `0.0`
///   stays `0.0` and must not become `0` or `0.00`;
/// * an object contributes its properties in order;
/// * an array contributes its own name once, then its name again before each
///   element.
///
/// Nothing is separated: the output is one unbroken line, which is the point —
/// no whitespace, no newlines, nothing a network or an editor can change.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A node of the document.
sealed class EtaValue {
  const EtaValue();
}

/// A leaf. Held as the exact string that goes on the wire, never as a number:
/// the moment an amount becomes a `double` its printed form stops being ours.
class EtaText extends EtaValue {
  const EtaText(this.value);

  final String value;
}

/// An ordered object. A `Map` would be enough in Dart — its literals preserve
/// insertion order — but the order is load-bearing here rather than incidental,
/// and a list of pairs says so.
class EtaObject extends EtaValue {
  const EtaObject(this.fields);

  final List<(String, EtaValue)> fields;

  /// Drops null values, so an absent optional field is absent rather than
  /// present and empty. ETA reads those differently.
  factory EtaObject.of(List<(String, EtaValue?)> fields) => EtaObject([
    for (final (name, value) in fields)
      if (value != null) (name, value),
  ]);

  EtaValue? operator [](String name) {
    for (final (key, value) in fields) {
      if (key == name) return value;
    }
    return null;
  }

  /// The same object without one property, used to hash a receipt without its
  /// own uuid in it.
  EtaObject without(String name) =>
      EtaObject([for (final field in fields) if (field.$1 != name) field]);

  /// The same object with one property replaced or appended, in place.
  EtaObject with_(String name, EtaValue value) {
    final replaced = [
      for (final field in fields)
        if (field.$1 == name) (name, value) else field,
    ];
    if (!fields.any((f) => f.$1 == name)) replaced.add((name, value));
    return EtaObject(replaced);
  }
}

class EtaArray extends EtaValue {
  const EtaArray(this.items);

  final List<EtaValue> items;
}

abstract final class EtaSerializer {
  /// The canonical text of [document], as one line.
  static String canonical(EtaObject document) {
    final buffer = StringBuffer();
    _object(buffer, document);
    return buffer.toString();
  }

  /// The receipt's uuid: SHA-256 of the canonical text, lowercase hex.
  ///
  /// Sixty-four characters, and the hash is taken over the document **without
  /// its own uuid** — a value cannot be part of what it is derived from.
  static String uuidOf(EtaObject receipt) {
    final header = receipt['header'];
    final withoutUuid = header is EtaObject
        ? receipt.with_('header', header.without('uuid'))
        : receipt;
    return sha256
        .convert(utf8.encode(canonical(withoutUuid)))
        .toString()
        .toLowerCase();
  }

  /// The bytes that get signed — the SHA-256 digest of the canonical text,
  /// this time **with** the uuid in place, because by then it is part of the
  /// document.
  static List<int> digestFor(EtaObject receipt) =>
      sha256.convert(utf8.encode(canonical(receipt))).bytes;

  static void _object(StringBuffer buffer, EtaObject object) {
    for (final (name, value) in object.fields) {
      switch (value) {
        case EtaText():
          buffer
            ..write('"${name.toUpperCase()}"')
            ..write('"${value.value}"');
        case EtaObject():
          buffer.write('"${name.toUpperCase()}"');
          _object(buffer, value);
        case EtaArray():
          // The array's own name once, then again before each element. Not a
          // typo in their spec: it is what makes a one-element array
          // distinguishable from the bare object.
          buffer.write('"${name.toUpperCase()}"');
          for (final item in value.items) {
            buffer.write('"${name.toUpperCase()}"');
            switch (item) {
              case EtaObject():
                _object(buffer, item);
              case EtaText():
                buffer.write('"${item.value}"');
              case EtaArray():
                // Not reachable from any receipt shape ETA publishes, and a
                // silent wrong answer here would be a rejected signature with
                // nothing to point at.
                throw UnsupportedError('An array of arrays has no serialization.');
            }
          }
      }
    }
  }

  /// The same tree as JSON, which is what is actually submitted.
  ///
  /// Rendered from the tree rather than from a parallel map, so the bytes that
  /// were hashed and the bytes that are sent describe the same document by
  /// construction.
  static Object? toJson(EtaValue value) => switch (value) {
    EtaText(:final value) => value,
    EtaObject(:final fields) => {
      for (final (name, child) in fields) name: toJson(child),
    },
    EtaArray(:final items) => [for (final item in items) toJson(item)],
  };
}
