package io.xorder.xorder_pos_cloud

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val secrets = KeystoreSecrets(applicationContext)
        // The Dart half is `MethodChannelAndroidSecrets` in
        // packages/shared_module (lib/data/config/android_keystore_secret_store.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "read" -> result.success(secrets.read(call.argument<String>("key")!!))
                        "write" -> {
                            secrets.write(call.argument<String>("key")!!, call.argument<String>("value")!!)
                            result.success(null)
                        }
                        "delete" -> {
                            secrets.delete(call.argument<String>("key")!!)
                            result.success(null)
                        }
                        "deleteAll" -> {
                            secrets.deleteAll()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    // The exception's class, never its message: nothing here
                    // may carry a secret into a log or a banner.
                    result.error("keystore_failure", error.javaClass.simpleName, null)
                }
            }
    }

    private companion object {
        const val CHANNEL = "io.xorder.pos/secrets"
    }
}
