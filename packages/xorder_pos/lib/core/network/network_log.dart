import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;

/// The one place the till builds an HTTP client.
///
/// Four classes used to construct their own `Dio` — the cloud API, the branch
/// sales API, the licence API and the connectivity probe — and nothing ran
/// between any of them and the wire. Debugging a refused claim meant reading
/// the sentence the wizard chose and guessing at the reply that chose it.
///
/// Every client now comes from here, and a development build logs each call
/// through [NetworkLog]. A release build gets the bare client: the log prints
/// request bodies, and a till in a business has no console to print to.
Dio posHttpClient(BaseOptions options) {
  final client = Dio(options);
  if (!kReleaseMode) client.interceptors.add(NetworkLog());
  return client;
}

/// Every request and reply, on the console, as the server saw and said it.
///
/// Three lines per call at most: the request with its body, the reply with
/// its status, time and body, or the transport failure with its reason. What
/// is printed is what was SENT — after the till trimmed, upper-cased or
/// lower-cased it — so a code that reads right on screen and wrong on the
/// wire shows up here as wrong.
///
/// Credentials are masked, not omitted: a bearer token keeps its last four
/// characters, which is enough to tell two tokens apart and not enough to use
/// one. A PIN, a password and a device token print as dots. The pairing code
/// and the licence key print in full — they are what is being debugged, they
/// are single-use or bound to this machine, and this is a development build.
class NetworkLog extends Interceptor {
  NetworkLog({void Function(String line)? sink, DateTime Function()? clock})
    : _sink = sink ?? debugPrint,
      _clock = clock ?? DateTime.now;

  final void Function(String line) _sink;
  final DateTime Function() _clock;

  static const _startedAt = 'pos.network.startedAt';

  /// Past this a body is a catalogue, not a clue.
  static const _bodyLimit = 2000;

  static const _secrets = {
    'password',
    'pin',
    'pin_hash',
    'device_token',
    'token',
    'jwt',
    'secret',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAt] = _clock();
    final auth = options.headers['Authorization'];
    _sink(
      'net → ${options.method} ${options.uri}'
      '${auth is String ? '  [${_maskBearer(auth)}]' : ''}',
    );
    _body(options.data);
    handler.next(options);
  }

  @override
  void onResponse(Response<Object?> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    _sink(
      'net ← ${response.statusCode} ${options.method} ${options.uri}'
      '${_elapsed(options)}',
    );
    _body(response.data);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final response = err.response;
    _sink(
      'net ✗ ${options.method} ${options.uri}${_elapsed(options)}: '
      '${err.type.name}'
      '${response?.statusCode != null ? ' HTTP ${response!.statusCode}' : ''}'
      '${err.message != null ? ' — ${err.message}' : ''}',
    );
    if (response != null) _body(response.data);
    handler.next(err);
  }

  String _elapsed(RequestOptions options) {
    final started = options.extra[_startedAt];
    if (started is! DateTime) return '';
    return ' (${_clock().difference(started).inMilliseconds} ms)';
  }

  void _body(Object? data) {
    if (data == null) return;
    final text = switch (data) {
      final String s => s.trim(),
      final Map<Object?, Object?> m => jsonEncode(_mask(m)),
      final List<Object?> l => jsonEncode(l.map(_maskAny).toList()),
      _ => data.toString(),
    };
    if (text.isEmpty) return;
    _sink(
      '      ${text.length > _bodyLimit ? '${text.substring(0, _bodyLimit)}… (${text.length} chars)' : text}',
    );
  }

  Map<String, Object?> _mask(Map<Object?, Object?> map) => {
    for (final entry in map.entries)
      '${entry.key}': _secrets.contains('${entry.key}'.toLowerCase())
          ? '•••'
          : _maskAny(entry.value),
  };

  Object? _maskAny(Object? value) => switch (value) {
    final Map<Object?, Object?> m => _mask(m),
    final List<Object?> l => l.map(_maskAny).toList(),
    _ => value,
  };

  static String _maskBearer(String header) {
    final token = header.startsWith('Bearer ') ? header.substring(7) : header;
    if (token.length <= 4) return 'Bearer •••';
    return 'Bearer …${token.substring(token.length - 4)}';
  }
}
