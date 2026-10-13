package ch.visin.purplehaze.config;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.DatabaseUtils;
import android.database.SQLException;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.util.Log;

import java.util.ArrayList;
import java.util.List;

public class ProfileRepository extends SQLiteOpenHelper {
    public static final String TAG = "ProfileRepository";

    private static final String DATABASE_NAME = "andiodine.db";
    private static final int DATABASE_VERSION = 4;
    static public final String TABLE_NAME_CONF = "configuration";
    static public final String COLUMN_CONF_ID = "id";
    static public final String COLUMN_CONF_NAME = "name";
    static public final String COLUMN_CONF_LAST_USED = "last_used";
    static public final String COLUMN_CONF_TUNNEL_NAMESERVER = "tunnel_nameserver";
    static public final String COLUMN_CONF_TOP_DOMAIN = "top_domain";
    static public final String COLUMN_CONF_PASSWORD = "password";
    static public final String COLUMN_CONF_NAMESERVER_MODE = "nameserver_mode";
    static public final String COLUMN_CONF_NAMESERVER = "nameserver";
    static public final String COLUMN_CONF_RAW_MODE = "raw_mode";
    static public final String COLUMN_CONF_LAZY_MODE = "lazy_mode";
    static public final String COLUMN_CONF_DEFAULT_ROUTE = "default_route";
    static public final String COLUMN_CONF_REQUEST_TYPE = "request_type";
    static public final String COLUMN_CONF_REQUEST_HOSTNAME_SIZE = "request_hostname_size";
    static public final String COLUMN_CONF_RESPONSE_FRAGMENT_SIZE = "response_fragment_size";

    public static final String COLUMN_CONF_SHARED_KEY = "shared_key";
    public static final String COLUMN_CONF_PROXY = "proxy";

    private static final String createStmt = "CREATE TABLE " + TABLE_NAME_CONF + " (" + //
            COLUMN_CONF_ID + " INTEGER PRIMARY KEY," + //
            COLUMN_CONF_NAME + " TEXT," + //
            COLUMN_CONF_LAST_USED + " INTEGER," + //
            COLUMN_CONF_TUNNEL_NAMESERVER + " TEXT," + //
            COLUMN_CONF_TOP_DOMAIN + " TEXT," + //
            COLUMN_CONF_PASSWORD + " TEXT," + //
            COLUMN_CONF_NAMESERVER_MODE + " TEXT," + //
            COLUMN_CONF_NAMESERVER + " TEXT," + //
            COLUMN_CONF_RAW_MODE + " INTEGER," + // Boolean stored as 1=true / 0=false
            COLUMN_CONF_LAZY_MODE + " INTEGER," + //
            COLUMN_CONF_DEFAULT_ROUTE + " INTEGER," + //
            COLUMN_CONF_REQUEST_TYPE + " TEXT," + //
            COLUMN_CONF_REQUEST_HOSTNAME_SIZE + " INTEGER," + //
            COLUMN_CONF_RESPONSE_FRAGMENT_SIZE + " INTEGER," +
            COLUMN_CONF_SHARED_KEY + " TEXT NOT NULL DEFAULT ''," +
            COLUMN_CONF_PROXY + " INTEGER NOT NULL DEFAULT 0," +
            "request_timeout INTEGER NOT NULL DEFAULT 1,downstream_encoding TEXT NOT NULL DEFAULT '',ipv6_transport INTEGER NOT NULL DEFAULT 0,encrypted INTEGER NOT NULL DEFAULT 1" + //
            ");";

    public ProfileRepository(Context context) {
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL(createStmt);
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        if (oldVersion < 2 && newVersion >= 2) {
            db.execSQL("ALTER TABLE " + TABLE_NAME_CONF + " ADD COLUMN shared_key TEXT NOT NULL DEFAULT ''");
            db.execSQL("ALTER TABLE " + TABLE_NAME_CONF + " ADD COLUMN proxy INTEGER NOT NULL DEFAULT 0");
        }
        if (oldVersion < 3 && newVersion >= 3) {
            db.execSQL("ALTER TABLE " + TABLE_NAME_CONF + " ADD COLUMN request_timeout INTEGER NOT NULL DEFAULT 1");
            db.execSQL("ALTER TABLE " + TABLE_NAME_CONF + " ADD COLUMN downstream_encoding TEXT NOT NULL DEFAULT ''");
            db.execSQL("ALTER TABLE " + TABLE_NAME_CONF + " ADD COLUMN ipv6_transport INTEGER NOT NULL DEFAULT 0");
        }
        if (oldVersion < 4 && newVersion >= 4) {
            db.execSQL("ALTER TABLE " + TABLE_NAME_CONF + " ADD COLUMN encrypted INTEGER NOT NULL DEFAULT 1");
            db.execSQL("UPDATE " + TABLE_NAME_CONF + " SET encrypted = CASE WHEN shared_key = '' THEN 0 ELSE 1 END");
        }
    }

    private ContentValues protectedValues(ContentValues plain) {
        ContentValues stored = new ContentValues(plain);
        for (String column : new String[]{COLUMN_CONF_PASSWORD, COLUMN_CONF_SHARED_KEY}) {
            if (stored.containsKey(column)) stored.put(column, SecretStore.encrypt(stored.getAsString(column)));
        }
        return stored;
    }

    private ConnectionProfile read(Cursor cursor, boolean unlock) {
        ContentValues values = new ContentValues();
        DatabaseUtils.cursorRowToContentValues(cursor, values);
        if (unlock) for (String column : new String[]{COLUMN_CONF_PASSWORD, COLUMN_CONF_SHARED_KEY})
            values.put(column, SecretStore.decrypt(values.getAsString(column)));
        return new ConnectionProfile(values);
    }

    public void insert(ContentValues config) throws SQLException {
        if (config.getAsLong(COLUMN_CONF_ID) != null)
            throw new SQLException("id must be null for insert");
        SQLiteDatabase writableDatabase = getWritableDatabase();
        long id = writableDatabase.insertOrThrow(TABLE_NAME_CONF, null, protectedValues(config));
        config.put(COLUMN_CONF_ID, id);
        Log.d(TAG, "Insert id=" + id);
    }

    public int update(ContentValues config) throws SQLException {
        if (config.getAsLong(COLUMN_CONF_ID) == null)
            throw new SQLException("id must NOT be null for update");
        SQLiteDatabase writableDatabase = getWritableDatabase();
        int rows = writableDatabase.update(TABLE_NAME_CONF, protectedValues(config), COLUMN_CONF_ID + " = ?",
                new String[]{config.getAsString(COLUMN_CONF_ID)});
        Log.d(TAG, "Update rows=" + rows);
        return rows;
    }

    public void delete(ContentValues config) throws SQLException {
        if (config.getAsLong(COLUMN_CONF_ID) == null)
            throw new SQLException("id must NOT be null for delete");
        SQLiteDatabase writableDatabase = getWritableDatabase();
        writableDatabase.delete(TABLE_NAME_CONF, COLUMN_CONF_ID + " = ?",
                new String[]{config.getAsString(COLUMN_CONF_ID)});
    }

    public ConnectionProfile selectById(Long id) throws SQLException {
        try (Cursor cursor = getReadableDatabase().query(TABLE_NAME_CONF, null, COLUMN_CONF_ID + " = ?",
                new String[]{id.toString()}, null, null, null)) {
            return cursor.moveToFirst() ? read(cursor, true) : null;
        }
    }

    public List<ConnectionProfile> selectAll() throws SQLException {
        List<ConnectionProfile> result = new ArrayList<>();
        try (Cursor cursor = getReadableDatabase().query(TABLE_NAME_CONF, null, null, null, null, null, null)) {
            while (cursor.moveToNext()) result.add(read(cursor, false));
        }
        return result;
    }

    public void insertOrUpdate(ContentValues config) {
        if (config.getAsLong(COLUMN_CONF_ID) == null) insert(config); else update(config);
    }
}
