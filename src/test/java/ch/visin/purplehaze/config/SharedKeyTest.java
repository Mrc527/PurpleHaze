package ch.visin.purplehaze.config;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.Base64;
public class SharedKeyTest {
    private final String key = Base64.getEncoder().encodeToString(new byte[32]);
    @Test public void paddedAndUnpaddedAndWhitespace() {
        assertArrayEquals(new byte[32], SharedKey.decode(key));
        assertArrayEquals(new byte[32], SharedKey.decode(key.replace("=", "")));
        assertArrayEquals(new byte[32], SharedKey.decode(" \n" + key + "\t"));
    }
    @Test public void legacySelectionIsExplicit() {
        assertNull(SharedKey.validate("", "legacy-password", false));
        assertNull(SharedKey.decode(null));
    }
    @Test public void rejectsMalformedAndWrongLength() {
        for (String invalid : new String[]{"garbage", key + "!", key.replace('A', '-'),
                Base64.getEncoder().encodeToString(new byte[31]), Base64.getEncoder().encodeToString(new byte[33])}) {
            assertThrows(IllegalArgumentException.class, () -> SharedKey.decode(invalid));
        }
    }
    @Test public void proxyNeedsKeyAndKeyExcludesLegacyPassword() {
        assertThrows(IllegalArgumentException.class, () -> SharedKey.validate("", "pwd", true));
        assertThrows(IllegalArgumentException.class, () -> SharedKey.validate(key, "pwd", false));
        assertEquals(32, SharedKey.validate(key, "", true).length);
    }
}
