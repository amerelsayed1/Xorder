import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:postgres/postgres.dart';

import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/domain/models/business_logo.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

/// Fetches one URL and returns its bytes, or null for anything but a clean 200.
typedef LogoFetch = Future<Uint8List?> Function(Uri url);

/// Brings the platform's logo down to a cloud till (XORD-021).
///
/// **The bundle names the logo, this step keeps a copy.** The seeder only
/// records `logo_remote_url` (it runs in a transaction that must not wait on a
/// network); this runs after it, on every sync pass, and downloads when the
/// address the platform wants differs from the one the stored bytes came from.
/// So a logo changed on the dashboard reaches the till on the next pass, and a
/// pass that could not reach the server simply tries again on the next.
///
/// **It can never hurt the till.** Every failure (no network, a non-200, a body
/// that is not a picture, a file too big, a database error) leaves the logo the
/// till already has exactly where it is and returns false. The start screen
/// reads the stored copy and never the network, so there is no failure here that
/// a cashier can see.
///
/// **No credentials leave the till.** The request is a bare GET: the device
/// token is for the platform's API, and the logo is a public file whose address
/// the platform itself supplied.
class LogoSync {
  LogoSync({
    required PosDatabase database,
    required this.config,
    required this.businessId,
    required String platformBase,
    LogoFetch? fetch,
  }) : _db = database,
       _platformBase = platformBase.replaceAll(RegExp(r'/+$'), ''),
       _fetch = fetch ?? _download;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int businessId;
  final String _platformBase;
  final LogoFetch _fetch;

  /// True when the stored logo changed (a new picture, or none any more).
  Future<bool> run() async {
    try {
      final rows = await _db.query(
        config,
        'SELECT logo_remote_url, logo_fetched_url FROM pos_businesses '
        'WHERE id = @r',
        parameters: {'r': businessId},
      );
      if (rows.isEmpty) return false;
      final wanted = rows.first[0] as String?;
      final held = rows.first[1] as String?;
      if (wanted == null || wanted == held) return false;

      final image = await _acquire(wanted);
      if (image == null) return false;

      // Guarded on the address still being the wanted one: a bundle that landed
      // while the download ran must not have its newer answer overwritten.
      final written = await _db.runTx(config, (tx) async {
        final result = await tx.execute(
          Sql.named(
            'UPDATE pos_businesses '
            '   SET logo_bytes = @bytes, logo_mime = @mime, '
            "       logo_source = 'platform', logo_fetched_url = @url, "
            '       logo_updated_at = now() '
            ' WHERE id = @r AND logo_remote_url = @url',
          ),
          parameters: {
            'r': businessId,
            'bytes': image.bytes,
            'mime': image.mime,
            'url': wanted,
          },
        );
        return result.affectedRows > 0;
      });
      return written;
    } on Object {
      return false;
    }
  }

  /// The address as sent first, then the same path on the platform the till
  /// actually talks to. The platform bakes its own `APP_URL` into the address,
  /// which is not always a host a till can reach (a platform behind a proxy, a
  /// local install); the path is the part that never changes.
  Future<LogoImage?> _acquire(String wanted) async {
    final sent = Uri.tryParse(wanted);
    if (sent == null || !(sent.scheme == 'http' || sent.scheme == 'https')) {
      return null;
    }
    final candidates = <Uri>[sent];
    final base = Uri.tryParse(_platformBase);
    if (base != null && base.hasAuthority && base.origin != sent.origin) {
      // `query: ''` would leave a stray `?` on an address that had none.
      candidates.add(
        base.replace(path: sent.path, query: sent.hasQuery ? sent.query : null),
      );
    }

    for (final url in candidates) {
      final bytes = await _fetch(url);
      if (bytes == null) continue;
      final check = BusinessLogoRules.inspect(bytes, fromPlatform: true);
      if (check.accepted) return check.image;
    }
    return null;
  }

  static Future<Uint8List?> _download(Uri url) async {
    try {
      final client = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.bytes,
          validateStatus: (status) => status == 200,
        ),
      );
      final reply = await client.getUri<List<int>>(url);
      final data = reply.data;
      if (data == null) return null;
      return data is Uint8List ? data : Uint8List.fromList(data);
    } on Object {
      return null;
    }
  }
}
