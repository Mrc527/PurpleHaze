package ch.visin.purplehaze.config;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Only authenticated ciphertext is written to the profile database. */
public final class SecretStore {
    private static final String ALIAS = "andiodine.profile-secrets.v1";
    private static final String PREFIX = "keystore-v1:";
    private static synchronized SecretKey key(boolean create) throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (store.containsAlias(ALIAS)) return (SecretKey) store.getKey(ALIAS, null);
        if (!create) throw new IllegalStateException("Profile key is unavailable; re-enter your credentials");
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
    public static String encrypt(String value) {
        if (value == null || value.isEmpty()) return "";
        byte[] plain = value.getBytes(StandardCharsets.UTF_8);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key(true));
            byte[] encrypted = cipher.doFinal(plain);
            byte[] result = new byte[12 + encrypted.length];
            System.arraycopy(cipher.getIV(), 0, result, 0, 12);
            System.arraycopy(encrypted, 0, result, 12, encrypted.length);
            return PREFIX + Base64.getEncoder().encodeToString(result);
        } catch (Exception error) {
            throw new IllegalStateException("Could not protect profile credentials", error);
        } finally { Arrays.fill(plain, (byte) 0); }
    }
    public static String decrypt(String value) {
        if (value == null || value.isEmpty()) return "";
        // Version 1 databases stored legacy passwords as plain text.
        if (!value.startsWith(PREFIX)) return value;
        byte[] plain = null;
        try {
            byte[] encrypted = Base64.getDecoder().decode(value.substring(PREFIX.length()));
            if (encrypted.length < 28) throw new IllegalArgumentException("Invalid encrypted value");
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(false), new GCMParameterSpec(128, encrypted, 0, 12));
            plain = cipher.doFinal(encrypted, 12, encrypted.length - 12);
            return new String(plain, StandardCharsets.UTF_8);
        } catch (Exception error) {
            throw new IllegalStateException("Could not unlock profile credentials; recreate the profile", error);
        } finally { if (plain != null) Arrays.fill(plain, (byte) 0); }
    }
}
