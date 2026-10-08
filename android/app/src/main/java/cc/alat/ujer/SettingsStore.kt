package cc.alat.ujer

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SettingsStore(context: Context) {
    private val preferences = context.getSharedPreferences("ujer", Context.MODE_PRIVATE)
    private val secrets = SecretStore(context)

    fun settings(provider: Provider = Provider.valueOf(preferences.getString("provider", Provider.OPENAI_COMPATIBLE.name)!!)): ProviderSettings {
        return ProviderSettings(
            provider,
            preferences.getString("baseUrl.${provider.name}", provider.defaultBaseUrl)!!,
            preferences.getString("model.${provider.name}", provider.defaultModel)!!,
        )
    }

    fun save(settings: ProviderSettings, token: String) {
        preferences.edit()
            .putString("provider", settings.provider.name)
            .putString("baseUrl.${settings.provider.name}", settings.baseUrl.trim())
            .putString("model.${settings.provider.name}", settings.model.trim())
            .apply()
        secrets.save(settings.provider, token.trim())
    }

    fun token(provider: Provider): String? = secrets.read(provider)
}

private class SecretStore(context: Context) {
    private val preferences = context.getSharedPreferences("ujer-secrets", Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun save(provider: Provider, value: String) {
        val name = provider.name
        if (value.isEmpty()) {
            preferences.edit().remove(name).apply()
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(name))
        val encrypted = cipher.iv + cipher.doFinal(value.toByteArray())
        preferences.edit().putString(name, Base64.encodeToString(encrypted, Base64.NO_WRAP)).apply()
    }

    fun read(provider: Provider): String? {
        val encoded = preferences.getString(provider.name, null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(provider.name), GCMParameterSpec(128, payload.copyOfRange(0, 12)))
            String(cipher.doFinal(payload.copyOfRange(12, payload.size)))
        } catch (_: Exception) {
            null
        }
    }

    private fun key(name: String): SecretKey {
        val alias = "cc.alat.ujer.$name"
        return (keyStore.getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply {
                init(
                    KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .build(),
                )
            }.generateKey()
    }
}
