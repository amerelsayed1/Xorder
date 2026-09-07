import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/config/platform_endpoint.dart';
import '../domain/license.dart';
import '../domain/license_verifier.dart';
import 'licence_service.dart';

/// Exchanges a typed licence key for a signed licence file.
///
/// Talks to the hosted platform directly rather than to the terminal's own
/// `baseUrl` — see [PlatformEndpoint] for why that distinction is load-bearing.
/// This is the *remote* half of activation; the other half is an operator
/// importing a file, and both land in the same `LicenceActivation.activate`.
class PlatformLicenceApi {
  PlatformLicenceApi({
    Dio? client,
    String Function()? baseUrl,
    String? Function()? tenantSlug,
    String Function()? deploymentMode,
  }) : _baseUrl = baseUrl ?? (() => PlatformEndpoint.base),
       _tenantSlug = tenantSlug ?? (() => null),
       _deploymentMode = deploymentMode ?? (() => 'cloud'),
       _client =
           client ??
           Dio(
             BaseOptions(
               // Generous, but finite. An installer standing in a restaurant
               // watching a spinner needs to be told to import the file instead,
               // not to wait indefinitely for a platform that is down.
               connectTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               // Non-2xx is data here, not an exception: a rejected key is an
               // ordinary answer and is reported as `LicenceKeyNotRecognised`.
               validateStatus: (_) => true,
             ),
           );

  final Dio _client;

  /// Where activation goes. The terminal's own configured platform once one
  /// exists — on the cloud path the platform that takes this till's money is
  /// the platform that licenses it, and a dev till pointed at localhost must
  /// not send its key to production. Before configuration (the licence-first
  /// offline wizard), the build-time [PlatformEndpoint.base] still applies.
  final String Function() _baseUrl;

  /// The tenant this terminal serves, when it already knows of one.
  ///
  /// Usually it does not, and that is the normal case rather than a gap: the
  /// wizard asks for the LICENCE first precisely because the licence is what
  /// supplies the tenant. At the moment this call is made there is nothing to
  /// send, and an offline customer has no tenant to send at all.
  ///
  /// The platform used to require it, which made "Activate online" impossible
  /// to satisfy from the wizard's first screen — a guaranteed 422 that the
  /// null-return below then dressed up as "that key was not recognised". The
  /// key is the credential; the slug is a cross-check, sent when it exists.
  final String? Function() _tenantSlug;
  final String Function() _deploymentMode;

  /// The licence, or WHY there isn't one.
  ///
  /// These used to collapse into a single null that the wizard reported as
  /// "that licence key was not recognised". That sentence is true of exactly
  /// one of the cases below and actively misleading in the rest — most sharply
  /// when a key minted on one platform is typed into a till built to ask
  /// another, where the key is perfect and the address is wrong. An installer
  /// told "not recognised" then goes looking for a typo that does not exist.
  Future<LicenceFetch> fetchByKey(
    String key,
    String terminalFingerprint,
  ) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return const LicenceFetch.failed(LicenceKeyNotRecognised());
    }

    final slug = _tenantSlug();
    // Outside the try: the catch has to be able to NAME the address it failed
    // to reach, which is the whole point of the diagnosis below.
    final base = _baseUrl().replaceAll(RegExp(r'/+$'), '');

    try {
      final response = await _client.postUri<Object?>(
        Uri.parse('$base/api/pos/licence/activate'),
        data: {
          'key': trimmed,
          'deployment_mode': _deploymentMode(),
          // Lets the issuer bind a newly activated licence to this
          // installation even though the server terminal row may come later.
          'fingerprint': terminalFingerprint,
          // Omitted entirely rather than sent as null when this terminal has
          // no tenant yet. When it DOES have one the platform still checks it,
          // so an installer activating against the wrong customer's key is
          // told so instead of quietly licensing the wrong restaurant.
          if (slug != null && slug.isNotEmpty) 'tenant_slug': slug,
        },
        options: Options(headers: const {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        // Diagnosable, not silent: this line is what turns "key not
        // recognised" into a five-second log read instead of an afternoon.
        debugPrint(
          'licence activate: $base answered HTTP ${response.statusCode}: '
          '${response.data}',
        );

        return LicenceFetch.failed(switch (response.statusCode) {
          // The platform's own taxonomy: it knows of no such key, or knows of
          // it and has revoked it. Both are answers about the KEY, so they name
          // the address — the key may be fine and this the wrong platform.
          404 => LicenceKeyNotRecognised(base),
          403 => const LicenceRevoked(),
          // Throttled. An installer retrying a key they believe in will find
          // this, and "not recognised" at that moment is the opposite of true.
          429 => const TooManyLicenceAttempts(),
          _ => LicenceServerRefused(base, response.statusCode ?? 0),
        });
      }

      final body = response.data;
      // The endpoint returns the licence document itself. Accept it either
      // decoded or as a raw string, because `validateStatus` lets through
      // responses whose content type the server did not set.
      final file = switch (body) {
        final String raw => LicenseFile.tryParse(raw),
        final Map<String, Object?> map => LicenseFile.tryParse(jsonEncode(map)),
        _ => null,
      };

      // A 200 that is not a licence means something is answering on this
      // address that is not the platform — a captive portal, a proxy, the
      // wrong service entirely. Not the key's fault either.
      return file == null
          ? LicenceFetch.failed(LicenceServerRefused(base, 200))
          : LicenceFetch.found(file);
    } on DioException catch (error) {
      debugPrint(
        'licence activate: $base threw ${error.type}: ${error.message}',
      );

      // A response that arrived and then failed to decode is NOT an
      // unreachable platform — it is a reachable address answering with
      // something that is not a licence, and telling an installer to check
      // their network would send them to fix the one thing that is working.
      final response = error.response;

      return LicenceFetch.failed(
        response == null
            ? LicenceServerUnreachable(base)
            : LicenceServerRefused(base, response.statusCode ?? 0),
      );
    }
  }
}
