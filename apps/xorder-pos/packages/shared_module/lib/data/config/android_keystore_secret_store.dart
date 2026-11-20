import 'package:flutter/services.dart';

import 'secret_store.dart';

/// The till's secrets on Android: sealed with a key that lives in the Android
/// Keystore, kept in the app's private storage (tablet-cloud-onboarding,
/// Stage 1; ADR-006).
///
/// The cryptography is native and lives in the app that ships on Android
/// (`apps/xorder_pos_cloud/android/.../KeystoreSecrets.kt`). It is reached
/// over a method channel rather than through a plugin so that the Windows and
/// macOS builds, which are what customers run today, gain no dependency.
///
/// **No fallback, ever.** A failure of any call is a [SecretStoreUnavailable]
/// and the till says so; a secret is never written to a file in the clear. The
/// failure carries the native exception's class name only — see
/// [AndroidSecretsFailure].
class AndroidKeystoreSecretStore implements SecretStore {
  AndroidKeystoreSecretStore({AndroidSecretsBackend? backend})
    : _backend = backend ?? const MethodChannelAndroidSecrets();

  final AndroidSecretsBackend _backend;

  @override
  bool get protectedByOperatingSystem => true;

  @override
  String get description => 'Android Keystore';

  Future<T> _guard<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on SecretStoreUnavailable {
      rethrow;
    } on Object catch (error) {
      throw SecretStoreUnavailable(
        store: description,
        operation: operation,
        cause: error,
      );
    }
  }

  @override
  Future<String?> read(String key) => _guard('read', () => _backend.read(key));

  @override
  Future<void> write(String key, String value) =>
      _guard('write', () => _backend.write(key, value));

  @override
  Future<void> delete(String key) =>
      _guard('delete', () => _backend.delete(key));

  @override
  Future<void> deleteAll() => _guard('delete', _backend.deleteAll);
}

/// The four native calls, behind a seam so everything around them is tested on
/// the machine that runs the suite. The real one is
/// [MethodChannelAndroidSecrets], proved on a device.
abstract interface class AndroidSecretsBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// What the native side reported. Never carries a secret: [code] is ours and
/// [nativeClass] is the Java exception's simple class name.
class AndroidSecretsFailure implements Exception {
  const AndroidSecretsFailure(this.code, [this.nativeClass]);

  final String code;
  final String? nativeClass;

  @override
  String toString() => nativeClass == null
      ? 'the keystore refused ($code)'
      : 'the keystore refused ($code, $nativeClass)';
}

/// The real backend: the `io.xorder.pos/secrets` channel `MainActivity`
/// answers.
class MethodChannelAndroidSecrets implements AndroidSecretsBackend {
  const MethodChannelAndroidSecrets();

  static const _channel = MethodChannel('io.xorder.pos/secrets');

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      // The message is the native exception's class name by construction
      // (MainActivity.kt); `details` is never read.
      throw AndroidSecretsFailure(error.code, error.message);
    } on MissingPluginException {
      throw const AndroidSecretsFailure('channel_missing');
    }
  }

  @override
  Future<String?> read(String key) => _call<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      _call<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) => _call<void>('delete', {'key': key});

  @override
  Future<void> deleteAll() => _call<void>('deleteAll');
}
