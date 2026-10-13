package ch.visin.purplehaze;

import android.content.Intent;

public final class NativeTunnel {
    private NativeTunnel() {}
    public static native int prepare(String server, String domain, String password, byte[] key,
                                     boolean proxy, boolean lazy, int hostnameSize, String queryType);
    public static native int configureTransport(int timeout, String encoding);
    public static native int handshake(boolean raw, int fragmentSize);
    public static native int tunnel(int fd);
    public static native void tunnelInterrupt();
    public static native void cleanup();
    public static native String getIp();
    public static native String getRemoteIp();
    public static native int getNetbits();
    public static native int getMtu();
    public static final String ACTION_LOG_MESSAGE = "ch.visin.purplehaze.NativeTunnel.ACTION_LOG_MESSAGE";
    public static final String EXTRA_MESSAGE = "message";
    @SuppressWarnings("unused")
    public static void log_callback(String message) {
        TunnelService service = TunnelService.instance;
        if (service != null) {
            service.appendLog(message);
            service.sendBroadcast(new Intent(ACTION_LOG_MESSAGE).setPackage(service.getPackageName())
                    .putExtra(EXTRA_MESSAGE, message));
        }
    }
    static { System.loadLibrary("iodine-client"); }
}
