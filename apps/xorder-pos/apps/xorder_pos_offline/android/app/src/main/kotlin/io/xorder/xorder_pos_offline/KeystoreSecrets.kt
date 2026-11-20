package io.xorder.xorder_pos_offline

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The till's secrets on Android: AES-256-GCM with a key that lives in the
 * Android Keystore and never leaves it. The ciphertext (a random IV followed
 * by the sealed value) is kept in a private SharedPreferences file, one entry
 * per secret key.
 *
 * The secret's name is bound in as additional authenticated data, so a value
 * copied from one entry to another fails to open instead of being handed to
 * the wrong caller (the same per-key binding the Windows DPAPI store has).
 *
 * There is no fallback. If the Keystore refuses, every call throws and the Dart
 * side shows the till's "secret store unavailable" message; a secret is never
 * written in the clear (ADR-006).
 *
 * Mirrors `AndroidKeystoreSecretStore` in `packages/shared_module`
 * (`lib/data/config/android_keystore_secret_store.dart`).
 */
class KeystoreSecrets(context: Context) {
    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    /** The value under [name], or null when there is none. */
    fun read(name: String): String? {
        val stored = prefs.getString(entry(name), null) ?: return null
        val raw = Base64.decode(stored, Base64.NO_WRAP)
        require(raw.size > IV_BYTES) { "stored secret is damaged" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(TAG_BITS, raw, 0, IV_BYTES),
        )
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val plain = cipher.doFinal(raw, IV_BYTES, raw.size - IV_BYTES)
        return String(plain, Charsets.UTF_8)
    }

    /** Keep [value] under [name], replacing what was there. */
    fun write(name: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val sealed = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        check(iv.size == IV_BYTES) { "unexpected IV length" }
        val stored = Base64.encodeToString(iv + sealed, Base64.NO_WRAP)
        // commit(), not apply(): a secret the caller was told is saved must be
        // on disk before the call returns.
        check(prefs.edit().putString(entry(name), stored).commit()) { "could not save" }
    }

    /** Remove [name]. Removing what is not there is not an error. */
    fun delete(name: String) {
        check(prefs.edit().remove(entry(name)).commit()) { "could not delete" }
    }

    /** Remove every secret, and the Keystore key with them. */
    fun deleteAll() {
        check(prefs.edit().clear().commit()) { "could not delete" }
        val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
        if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS)
    }

    private fun entry(name: String) = "s_$name"

    private companion object {
        const val PROVIDER = "AndroidKeyStore"
        const val ALIAS = "io.xorder.pos.secrets"
        const val PREFS = "xorder_secrets"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
