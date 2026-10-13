package ch.visin.purplehaze;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;
import ch.visin.purplehaze.config.*;
import static org.junit.Assert.*;
import java.util.Base64;

@RunWith(AndroidJUnit4.class)
public class ProfileSecurityTest {
    @Test public void credentialsRoundTripButNeverAppearInDatabase() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        ProfileRepository database = new ProfileRepository(context);
        String key = Base64.getEncoder().encodeToString(new byte[32]);
        ContentValues profile = new ContentValues();
        profile.put(ProfileRepository.COLUMN_CONF_NAME, "Storage test");
        profile.put(ProfileRepository.COLUMN_CONF_SHARED_KEY, key);
        profile.put(ProfileRepository.COLUMN_CONF_PASSWORD, "legacy-test-secret");
        database.insert(profile);
        try {
            long id = profile.getAsLong(ProfileRepository.COLUMN_CONF_ID);
            try (Cursor cursor = database.getReadableDatabase().query(ProfileRepository.TABLE_NAME_CONF,
                    new String[]{"shared_key", "password"}, "id=?", new String[]{"" + id}, null, null, null)) {
                assertTrue(cursor.moveToFirst());
                assertTrue(cursor.getString(0).startsWith("keystore-v1:"));
                assertFalse(cursor.getString(0).contains(key));
                assertFalse(cursor.getString(1).contains("legacy-test-secret"));
            }
            assertEquals(key, database.selectById(id).getSharedKey());
            assertEquals("legacy-test-secret", database.selectById(id).getPassword());
            String cipher = SecretStore.encrypt(key);
            assertEquals(key, SecretStore.decrypt(cipher));
            String tampered = cipher.substring(0, cipher.length() - 5) + "AAAAA";
            assertThrows(IllegalStateException.class, () -> SecretStore.decrypt(tampered));
        } finally { database.delete(profile); database.close(); }
    }
    @Test public void versionOneSchemaKeepsLegacyProfiles() {
        try (SQLiteDatabase db = SQLiteDatabase.create(null)) {
            db.execSQL("CREATE TABLE configuration (id INTEGER PRIMARY KEY, name TEXT, password TEXT)");
            db.execSQL("INSERT INTO configuration(name,password) VALUES('existing','old-password')");
            ProfileRepository helper = new ProfileRepository(InstrumentationRegistry.getInstrumentation().getTargetContext());
            helper.onUpgrade(db, 1, 2);
            try (Cursor c = db.rawQuery("SELECT name,password,shared_key,proxy FROM configuration", null)) {
                assertTrue(c.moveToFirst()); assertEquals("existing", c.getString(0));
                assertEquals("old-password", c.getString(1)); assertEquals("", c.getString(2)); assertEquals(0, c.getInt(3));
            }
            helper.close();
        }
    }
    @Test public void versionTwoMigrationPreservesCredentialsAndAuthentication() {
        try (SQLiteDatabase db = SQLiteDatabase.create(null)) {
            db.execSQL("CREATE TABLE configuration(id INTEGER PRIMARY KEY,name TEXT,shared_key TEXT,password TEXT,proxy INTEGER)");
            db.execSQL("INSERT INTO configuration VALUES(1,'encrypted','keystore-v1:opaque','',1),(2,'legacy','','legacy-password',0)");
            ProfileRepository helper = new ProfileRepository(InstrumentationRegistry.getInstrumentation().getTargetContext());
            helper.onUpgrade(db,2,4);
            try(Cursor c=db.rawQuery("SELECT name,shared_key,password,proxy,request_timeout,downstream_encoding,ipv6_transport,encrypted FROM configuration ORDER BY id",null)) {
                assertTrue(c.moveToFirst());assertEquals("encrypted",c.getString(0));assertEquals("keystore-v1:opaque",c.getString(1));assertEquals(1,c.getInt(3));assertEquals(1,c.getInt(4));assertEquals("",c.getString(5));assertEquals(0,c.getInt(6));assertEquals(1,c.getInt(7));
                assertTrue(c.moveToNext());assertEquals("legacy-password",c.getString(2));assertEquals(0,c.getInt(7));
            } finally { helper.close(); }
        }
    }
    @Test public void profileEditsAndDeletionKeepOtherCredentialsIsolated() {
        ProfileRepository db=new ProfileRepository(InstrumentationRegistry.getInstrumentation().getTargetContext());
        ConnectionProfile a=ConnectionProfile.create(), b=ConnectionProfile.create();
        a.setName("Alpha");a.setTopDomain("a.example");a.setRequestTimeout(3);a.setDownstreamEncoding("base64");a.setIpv6Transport(true);
        b.setName("Beta");b.setTopDomain("b.example");
        byte[] bytes=new byte[32];java.util.Arrays.fill(bytes,(byte)7);String keyA=Base64.getEncoder().encodeToString(bytes);
        java.util.Arrays.fill(bytes,(byte)9);String keyB=Base64.getEncoder().encodeToString(bytes);
        a.getContentValues().put("shared_key",keyA);b.getContentValues().put("shared_key",keyB);
        db.insert(a.getContentValues());db.insert(b.getContentValues());
        try {
            a.setName("Alpha updated");a.setDownstreamEncoding("base128");db.update(a.getContentValues());
            assertEquals("Alpha updated",db.selectById(a.getId()).getName());assertEquals("base128",db.selectById(a.getId()).getDownstreamEncoding());assertEquals(3,db.selectById(a.getId()).getRequestTimeout());assertTrue(db.selectById(a.getId()).getIpv6Transport());
            assertEquals(keyA,db.selectById(a.getId()).getSharedKey());assertEquals(keyB,db.selectById(b.getId()).getSharedKey());
            assertTrue(db.selectAll().stream().filter(p->p.getId().equals(a.getId())).findFirst().get().getSharedKey().startsWith("keystore-v1:"));
            db.delete(a.getContentValues());assertNull(db.selectById(a.getId()));assertEquals("Beta",db.selectById(b.getId()).getName());assertEquals(keyB,db.selectById(b.getId()).getSharedKey());
        } finally {db.delete(a.getContentValues());db.delete(b.getContentValues());db.close();}
    }
    @Test public void nativeConfigurationRejectsInvalidKeyAndProxyDowngrade() {
        try {
            assertEquals(-1, NativeTunnel.prepare("127.0.0.1", "test.example", "", new byte[31], false, true, 255, ""));
            assertEquals(-1, NativeTunnel.prepare("127.0.0.1", "test.example", "", null, true, true, 255, ""));
            assertEquals(-1, NativeTunnel.prepare("127.0.0.1", "test.example", "password", new byte[32], false, true, 255, ""));
            assertTrue(NativeTunnel.prepare("127.0.0.1", "test.example", "", new byte[32], true, true, 255, "") >= 0);
            assertEquals(0,NativeTunnel.configureTransport(4,"base128"));
            assertEquals(1,NativeTunnel.configureTransport(0,""));
            assertEquals(1,NativeTunnel.configureTransport(1,"invalid"));
            NativeTunnel.cleanup();
            assertTrue(NativeTunnel.prepare("127.0.0.1", "test.example", "legacy", null, false, true, 255, "") >= 0);
        } finally { NativeTunnel.cleanup(); }
    }
}
