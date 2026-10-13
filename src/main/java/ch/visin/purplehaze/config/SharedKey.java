package ch.visin.purplehaze.config;

import java.util.Base64;

/** Strict shared-key validation, shared by the editor and the service. */
public final class SharedKey {
    private SharedKey() {}
    public static byte[] decode(String text) {
        String normalized = text == null ? "" : text.replaceAll("\\s", "");
        if (normalized.isEmpty()) return null;
        if (!normalized.matches("[A-Za-z0-9+/]{43}=?"))
            throw new IllegalArgumentException("The shared key must be Base64 encoding of exactly 32 bytes");
        byte[] key = Base64.getDecoder().decode(normalized);
        if (key.length != 32) throw new IllegalArgumentException("The shared key must contain 32 bytes");
        return key;
    }
    public static byte[] validate(String key, String password, boolean proxy) {
        byte[] decoded = decode(key);
        if (proxy && decoded == null)
            throw new IllegalArgumentException("Proxy requires an encrypted connection: enter the shared key");
        if (decoded != null && password != null && !password.isEmpty())
            throw new IllegalArgumentException("Clear the legacy password when using a shared key");
        return decoded;
    }
}
