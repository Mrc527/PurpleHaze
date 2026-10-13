package ch.visin.purplehaze;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.IntentFilter;
import android.os.Build;
final class AppBroadcasts {
    private AppBroadcasts() {}
    static void register(Context context, BroadcastReceiver receiver, IntentFilter filter) {
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        else context.registerReceiver(receiver, filter, context.getPackageName() + ".INTERNAL", null);
    }
}
