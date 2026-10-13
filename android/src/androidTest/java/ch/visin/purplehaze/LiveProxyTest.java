package ch.visin.purplehaze;
import android.content.*;
import android.os.Bundle;
import android.net.VpnService;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.*;
import org.junit.runner.RunWith;
import ch.visin.purplehaze.config.*;
import static org.junit.Assert.*;
import java.io.*;
import java.net.*;
import java.nio.file.Files;
import java.util.Base64;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

/** Opt-in: key is supplied privately to the emulator, never embedded in the APK. */
@RunWith(AndroidJUnit4.class)
public class LiveProxyTest {
    @Test public void encryptedProxyCarriesDeviceTcpUdpAndDns() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        Assume.assumeTrue(args.containsKey("live.server"));
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertNull("Grant VPN authorization on the disposable emulator first", VpnService.prepare(context));
        byte[] key = Files.readAllBytes(new File(context.getFilesDir(), "test-server.key").toPath());
        assertEquals(32, key.length);
        ProfileRepository db = new ProfileRepository(context);
        ConnectionProfile conf = new ConnectionProfile();
        conf.setName("Encrypted proxy test"); conf.setTopDomain(args.getString("live.domain"));
        conf.setTunnelNameserver(args.getString("live.server")); conf.setPassword("");
        conf.setRequestType(ConnectionProfile.RequestType.NULL); conf.setLazyMode(true);
        conf.setRawMode("true".equals(args.getString("live.raw", "true")));
        conf.setDefaultRoute(false); // Proxy must override this.
        conf.setNameserverMode(ConnectionProfile.NameserverMode.LEAVE_DEFAULT);
        conf.setNameserver(""); conf.setRequestHostnameSize(255); conf.setResponseFragmentSize(1100);
        conf.getContentValues().put(ProfileRepository.COLUMN_CONF_SHARED_KEY, Base64.getEncoder().encodeToString(key));
        conf.getContentValues().put(ProfileRepository.COLUMN_CONF_PROXY, 1);
        java.util.Arrays.fill(key, (byte)0);
        db.insert(conf.getContentValues());
        CountDownLatch connected = new CountDownLatch(1), ended = new CountDownLatch(1);
        AtomicReference<String> error = new AtomicReference<>();
        BroadcastReceiver receiver = new BroadcastReceiver() {
            public void onReceive(Context ignored, Intent intent) {
                if (TunnelService.ACTION_STATUS_CONNECTED.equals(intent.getAction())) connected.countDown();
                if (TunnelService.ACTION_STATUS_IDLE.equals(intent.getAction())) ended.countDown();
                if (TunnelService.ACTION_STATUS_ERROR.equals(intent.getAction())) {
                    error.set(intent.getStringExtra(TunnelService.EXTRA_ERROR_MESSAGE));
                    connected.countDown(); ended.countDown();
                }
            }
        };
        IntentFilter filter = new IntentFilter(TunnelService.ACTION_STATUS_CONNECTED);
        filter.addAction(TunnelService.ACTION_STATUS_ERROR); filter.addAction(TunnelService.ACTION_STATUS_IDLE);
        AppBroadcasts.register(context, receiver, filter);
        android.app.Activity activity = InstrumentationRegistry.getInstrumentation().startActivitySync(
                new Intent(context, HomeActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            context.startForegroundService(new Intent(context, TunnelService.class)
                    .setAction(TunnelService.ACTION_CONTROL_CONNECT)
                    .putExtra(TunnelService.EXTRA_CONFIGURATION_ID, conf.getId()));
            assertTrue("Timed out connecting", connected.await(90, TimeUnit.SECONDS));
            assertNull(error.get(), error.get());
            android.util.Log.i("LiveProxyTest", "Connected; testing UDP DNS");
            byte[] query = new byte[]{6,2,1,0,0,1,0,0,0,0,0,0,7,'e','x','a','m','p','l','e',3,'c','o','m',0,0,1,0,1};
            try (DatagramSocket socket = new DatagramSocket()) {
                socket.setSoTimeout(15000);
                socket.send(new DatagramPacket(query, query.length, InetAddress.getByName("1.1.1.1"), 53));
                byte[] bytes = new byte[4096]; DatagramPacket reply = new DatagramPacket(bytes, bytes.length);
                socket.receive(reply);
                assertTrue(reply.getLength() > query.length); assertEquals(6, bytes[0]); assertEquals(2, bytes[1]);
                assertEquals(0, bytes[3] & 15);
            }
            android.util.Log.i("LiveProxyTest", "UDP DNS passed; testing HTTPS");
            assertEquals(200, http("https://example.com", null));
            ByteArrayOutputStream egress = new ByteArrayOutputStream();
            assertEquals(200, http("https://api.ipify.org", egress));
            if (args.containsKey("live.egress")) assertEquals(args.getString("live.egress"), egress.toString("UTF-8").trim());
            try (Socket ipv6 = new Socket()) {
                try { ipv6.connect(new InetSocketAddress("2606:4700:4700::1111", 443), 2500); fail("IPv6 escaped the VPN"); }
                catch (IOException expected) { /* unsupported family is blocked */ }
            }
        } finally {
            context.sendBroadcast(new Intent(TunnelService.ACTION_CONTROL_DISCONNECT).setPackage(context.getPackageName()));
            ended.await(15, TimeUnit.SECONDS);
            context.unregisterReceiver(receiver);
            db.delete(conf.getContentValues()); db.close();
            InstrumentationRegistry.getInstrumentation().runOnMainSync(activity::finish);
        }
    }
    private int http(String url, ByteArrayOutputStream body) throws Exception {
        HttpURLConnection request = (HttpURLConnection)new URL(url).openConnection();
        request.setConnectTimeout(20000); request.setReadTimeout(20000);
        try {
            int code = request.getResponseCode();
            try (InputStream stream = request.getInputStream()) {
                byte[] buffer = new byte[4096]; int n;
                while ((n = stream.read(buffer)) != -1) if (body != null) body.write(buffer, 0, n);
            }
            return code;
        } finally { request.disconnect(); }
    }
}
