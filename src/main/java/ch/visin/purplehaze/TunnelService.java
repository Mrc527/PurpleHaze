package ch.visin.purplehaze;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.VpnService;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import ch.visin.purplehaze.config.ProfileRepository;
import ch.visin.purplehaze.config.ConnectionProfile;
import ch.visin.purplehaze.config.SharedKey;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

public class TunnelService extends VpnService implements Runnable {
    public static volatile TunnelService instance;
    public static final String EXTRA_CONFIGURATION_ID = "configuration_id";
    /**
     * String
     */
    public static final String EXTRA_ERROR_MESSAGE = "message";

    /**
     * Intent to connect to VPN Connection
     * CONTROL_CONNECT(EXTRA_CONFIGURATION_ID)
     */

    public static final String ACTION_CONTROL_CONNECT = "ch.visin.purplehaze.TunnelService.CONTROL_CONNECT";
    /**
     * Intent to close the vpn connection
     */
    public static final String ACTION_CONTROL_DISCONNECT = "ch.visin.purplehaze.TunnelService.CONTROL_DISCONNECT";

    /**
     * Intent to request a new status update
     */
    public static final String ACTION_CONTROL_UPDATE = "ch.visin.purplehaze.TunnelService.CONTROL_UPDATE";

    /**
     * Broadcast Action: The tunnel service is idle. This Action contains no
     * extras.
     */
    public static final String ACTION_STATUS_IDLE = "ch.visin.purplehaze.TunnelService.STATUS_IDLE";

    /**
     * Broadcast Action: The user sent CONTROL_CONNECT and the vpn service is
     * trying to connect.
     *
     * @see #EXTRA_CONFIGURATION_ID
     */
    public static final String ACTION_STATUS_CONNECT = "ch.visin.purplehaze.TunnelService.STATUS_CONNECT";
    /**
     * Broadcast Action: The tunnel is connected
     *
     * @see #EXTRA_CONFIGURATION_ID
     */
    public static final String ACTION_STATUS_CONNECTED = "ch.visin.purplehaze.TunnelService.STATUS_CONNECTED";
    /**
     * Broadcast Action: The tunnel was disconnected
     *
     * @see #EXTRA_CONFIGURATION_ID
     */
    public static final String ACTION_STATUS_DISCONNECT = "ch.visin.purplehaze.TunnelService.STATUS_DISCONNECT";
    /**
     * Broadcast Action: An error occured
     *
     * @see #EXTRA_CONFIGURATION_ID
     * @see #EXTRA_ERROR_MESSAGE
     */
    public static final String ACTION_STATUS_ERROR = "ch.visin.purplehaze.TunnelService.STATUS_ERROR";


    private static final AtomicBoolean NATIVE_BUSY = new AtomicBoolean();
    private static final Object NATIVE_LOCK = new Object();
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile Thread worker;
    private volatile boolean stopping;
    private ConnectionProfile configuration;
    private ProfileRepository database;
    private volatile String status = ACTION_STATUS_IDLE;
    private volatile String message;
    private Long configurationId;
    private static final String CHANNEL = "iodine-vpn";
    private final java.util.ArrayDeque<String> log = new java.util.ArrayDeque<>();
    public synchronized void appendLog(String line) {
        while (log.size() >= 250) log.removeFirst();
        log.addLast(line.trim());
    }
    public synchronized String getLog() { return android.text.TextUtils.join("\n", log); }
    public boolean isBusy() { return worker != null; }
    public Long getProfileId() { return configurationId; }
    public String getStatus() { return status; }
    private final BroadcastReceiver controls = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (ACTION_CONTROL_DISCONNECT.equals(intent.getAction())) shutdown();
            else if (ACTION_CONTROL_UPDATE.equals(intent.getAction())) sendStatus();
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        instance = this;
        database = new ProfileRepository(this);
        getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel(CHANNEL, "PurpleHaze VPN", NotificationManager.IMPORTANCE_LOW));
        IntentFilter filter = new IntentFilter(ACTION_CONTROL_DISCONNECT);
        filter.addAction(ACTION_CONTROL_UPDATE);
        AppBroadcasts.register(this, controls, filter);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_CONTROL_CONNECT.equals(intent.getAction())) {
            startForeground(602, notification(getString(R.string.connect)));
            if (worker != null || !NATIVE_BUSY.compareAndSet(false, true)) {
                if (worker == null) {
                    setStatus(ACTION_STATUS_ERROR, "The previous VPN is still stopping; retry in a moment");
                    stopForeground(STOP_FOREGROUND_REMOVE);
                    stopSelf();
                }
                return START_NOT_STICKY;
            }
            try {
                long id = intent.getLongExtra(EXTRA_CONFIGURATION_ID, -1);
                configuration = database.selectById(id);
                if (configuration == null) throw new IllegalArgumentException("Select a connection profile");
                configurationId = id;
                synchronized (this) { log.clear(); }
                stopping = false;
                setStatus(ACTION_STATUS_CONNECT, null);
                worker = new Thread(this, "iodine-vpn");
                worker.start();
            } catch (Exception error) {
                NATIVE_BUSY.set(false);
                setStatus(ACTION_STATUS_ERROR, error.getMessage());
                stopForeground(STOP_FOREGROUND_REMOVE);
                stopSelf();
            }
        } else if (intent != null && ACTION_CONTROL_DISCONNECT.equals(intent.getAction())) shutdown();
        else sendStatus();
        return START_NOT_STICKY;
    }

    private Notification notification(String text) {
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, HomeActivity.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop = PendingIntent.getService(this, 1,
                new Intent(this, TunnelService.class).setAction(ACTION_CONTROL_DISCONNECT),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_vpn)
                .setContentTitle("PurpleHaze").setContentText(text).setOngoing(true)
                .setContentIntent(open).addAction(new Notification.Action.Builder(null,
                        getString(R.string.close), stop).build()).build();
    }

    private void shutdown() {
        stopping = true;
        if (worker != null) {
            setStatus(ACTION_STATUS_DISCONNECT, null);
            synchronized (NATIVE_LOCK) { NativeTunnel.tunnelInterrupt(); }
            worker.interrupt();
        } else {
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
        }
    }
    @Override public void onRevoke() { shutdown(); }
    @Override public void onDestroy() {
        shutdown();
        if (instance == this) instance = null;
        unregisterReceiver(controls);
        database.close();
        super.onDestroy();
    }
    private void setStatus(String action, String detail) {
        status = action; message = detail; sendStatus();
    }
    private void sendStatus() {
        if (instance != this) return;
        Intent intent = new Intent(status).setPackage(getPackageName());
        if (configurationId != null) intent.putExtra(EXTRA_CONFIGURATION_ID, configurationId);
        if (message != null) intent.putExtra(EXTRA_ERROR_MESSAGE, message);
        sendBroadcast(intent);
    }
    private void checkStopped() throws InterruptedException {
        if (stopping || Thread.currentThread().isInterrupted()) throw new InterruptedException();
    }
    private Network underlyingNetwork(ConnectivityManager cm) {
        Network active = cm.getActiveNetwork();
        NetworkCapabilities caps = active == null ? null : cm.getNetworkCapabilities(active);
        if (caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return active;
        for (Network candidate : cm.getAllNetworks()) {
            caps = cm.getNetworkCapabilities(candidate);
            if (caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return candidate;
        }
        throw new IllegalStateException("No underlying network available");
    }
    private InetAddress ipv4(Network network, String host) throws Exception {
        for (InetAddress address : network.getAllByName(host))
            if (address instanceof Inet4Address) return address;
        throw new IllegalArgumentException("No IPv4 address for " + host);
    }
    @Override public void run() {
        byte[] key = null;
        ParcelFileDescriptor tunnel = null;
        boolean failed = false;
        try {
            if (configuration.isEncrypted() && configuration.getSharedKey().trim().isEmpty())
                throw new IllegalArgumentException("Encrypted profiles require a shared key");
            if (!configuration.isEncrypted() && (!configuration.getSharedKey().isEmpty() || configuration.getProxy()))
                throw new IllegalArgumentException("Legacy profiles cannot use a shared key or server proxy");
            key = SharedKey.validate(configuration.getSharedKey(), configuration.getPassword(), configuration.getProxy());
            int hostSize = configuration.getRequestHostnameSize();
            int fragments = configuration.getResponseFragmentSize();
            if (hostSize < 100 || hostSize > 255 || fragments < 0 || fragments > 65535)
                throw new IllegalArgumentException("Invalid hostname or fragment size");
            if (configuration.getRequestTimeout() < 1 || configuration.getRequestTimeout() > 60)
                throw new IllegalArgumentException("Request timeout must be between 1 and 60 seconds");
            ConnectivityManager cm = getSystemService(ConnectivityManager.class);
            Network network = underlyingNetwork(cm);
            String server = configuration.getTunnelNameserver();
            if (server == null || server.trim().isEmpty()) {
                LinkProperties properties = cm.getLinkProperties(network);
                if (properties != null) for (InetAddress candidate : properties.getDnsServers()) {
                    if (configuration.getIpv6Transport() || candidate instanceof Inet4Address) { server = candidate.getHostAddress(); break; }
                }
            }
            if (server == null || server.trim().isEmpty()) throw new IllegalArgumentException("Enter an IPv4 tunnel nameserver");
            if (configuration.getIpv6Transport()) server = network.getAllByName(server.trim())[0].getHostAddress();
            else server = ipv4(network, server.trim()).getHostAddress();
            int fd;
            synchronized (NATIVE_LOCK) {
                checkStopped();
                fd = NativeTunnel.prepare(server, configuration.getTopDomain(), configuration.getPassword(), key,
                        configuration.getProxy(), configuration.getLazyMode(), hostSize,
                        configuration.getRequestType().getIodineName());
            }
            if (key != null) { Arrays.fill(key, (byte) 0); key = null; }
            if (fd < 0) throw new IllegalArgumentException("Invalid profile or unable to create transport socket");
            if (NativeTunnel.configureTransport(configuration.getRequestTimeout(), configuration.getDownstreamEncoding()) != 0)
                throw new IllegalArgumentException("Invalid transport settings");
            // Protect AND bind before handshake and before installing any VPN route.
            if (!protect(fd)) throw new IllegalStateException("Could not protect the iodine transport socket");
            try (ParcelFileDescriptor transport = ParcelFileDescriptor.fromFd(fd)) {
                network.bindSocket(transport.getFileDescriptor());
            }
            checkStopped();
            if (NativeTunnel.handshake(configuration.getRawMode(), fragments) != 0)
                throw new IllegalStateException("Handshake failed: check server, key and proxy support");
            checkStopped();
            Builder builder = new Builder().setSession(configuration.getName()).setBlocking(true)
                    .setUnderlyingNetworks(new Network[]{network});
            String ip = NativeTunnel.getIp();
            int bits = NativeTunnel.getNetbits();
            builder.addAddress(ip, bits).setMtu(NativeTunnel.getMtu());
            byte[] subnet = InetAddress.getByName(ip).getAddress();
            for (int i = 0; i < 4; i++) {
                int keep = Math.max(0, Math.min(8, bits - i * 8));
                subnet[i] = (byte) (subnet[i] & (0xff << (8 - keep)));
            }
            builder.addRoute(InetAddress.getByAddress(subnet), bits);
            if (configuration.getProxy() || configuration.getDefaultRoute()) builder.addRoute("0.0.0.0", 0);
            if (configuration.getProxy()) {
                String dns = configuration.getNameserverMode() == ConnectionProfile.NameserverMode.SET_CUSTOM
                        ? configuration.getNameserver() : "1.1.1.1";
                if (dns == null || dns.trim().isEmpty()) throw new IllegalArgumentException("Enter the custom DNS server");
                builder.addDnsServer(ipv4(network, dns.trim()));
            } else {
                switch (configuration.getNameserverMode()) {
                    case SET_SERVER_TUNNEL_IP: builder.addDnsServer(NativeTunnel.getRemoteIp()); break;
                    case SET_CUSTOM:
                        InetAddress dnsAddress = ipv4(network, configuration.getNameserver());
                        builder.addDnsServer(dnsAddress);
                        if (!configuration.getDefaultRoute()) builder.addRoute(dnsAddress, 32);
                        break;
                    default: break;
                }
            }
            // No IPv6 address/route/allowFamily: Android blocks this unsupported
            // address family instead of sending it over the underlying network.
            checkStopped();
            tunnel = builder.establish();
            if (tunnel == null) throw new IllegalStateException("VPN permission was revoked");
            checkStopped();
            setStatus(ACTION_STATUS_CONNECTED, null);
            getSystemService(NotificationManager.class).notify(602, notification(configuration.getProxy()
                    ? "Encrypted · TCP / UDP / DNS proxy" : configuration.getSharedKey().isEmpty()
                    ? "Legacy unencrypted tunnel" : "Encrypted tunnel"));
            int result = NativeTunnel.tunnel(tunnel.getFd());
            checkStopped();
            throw new IllegalStateException("Tunnel disconnected" + (result == 0 ? "" : " (network error)"));
        } catch (InterruptedException ignored) {
            // Explicit stop; cleanup below restores the system network automatically.
        } catch (Exception error) {
            if (!stopping) {
                failed = true;
                message = error.getMessage();
            }
        } finally {
            if (key != null) Arrays.fill(key, (byte) 0);
            if (tunnel != null) try { tunnel.close(); } catch (Exception ignored) {}
            synchronized (NATIVE_LOCK) { NativeTunnel.cleanup(); }
            NATIVE_BUSY.set(false);
            final boolean connectionFailed = failed;
            main.post(() -> {
                worker = null;
                configuration = null;
                if (connectionFailed) setStatus(ACTION_STATUS_ERROR, message);
                else setStatus(ACTION_STATUS_IDLE, null);
                stopForeground(STOP_FOREGROUND_REMOVE);
                stopSelf();
            });
        }
    }
}
