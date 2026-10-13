package ch.visin.purplehaze;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.ScrollView;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.Test;
import org.junit.Assume;
import org.junit.runner.RunWith;
import ch.visin.purplehaze.config.*;
import java.io.File;
import java.io.FileOutputStream;
import java.util.Base64;
import static org.junit.Assert.*;

/** Opt-in screenshots with dummy profiles; the production editor always blocks screenshots. */
@RunWith(AndroidJUnit4.class)
public class ScreenshotTest {
    private final Instrumentation instrumentation=InstrumentationRegistry.getInstrumentation();
    private final Context context=instrumentation.getTargetContext();
    private void capture(String name)throws Exception {
        instrumentation.waitForIdleSync();Thread.sleep(600);
        Bitmap bitmap=instrumentation.getUiAutomation().takeScreenshot();assertNotNull(bitmap);
        try(FileOutputStream output=new FileOutputStream(new File(context.getFilesDir(),name))){assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,output));}finally{bitmap.recycle();}
    }
    private ScrollView scroll(View view){if(view instanceof ScrollView)return(ScrollView)view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){ScrollView result=scroll(((ViewGroup)view).getChildAt(i));if(result!=null)return result;}return null;}
    @Test public void captureBrandedProfiles()throws Exception {
        Assume.assumeTrue("true".equals(InstrumentationRegistry.getArguments().getString("screenshots")));
        ProfileRepository db=new ProfileRepository(context);ConnectionProfile primary=ConnectionProfile.create(),backup=ConnectionProfile.create();
        primary.setName("Home · mi-gtw");primary.setTopDomain("i.visin.ch");primary.setTunnelNameserver("2.238.71.209");
        primary.getContentValues().put("shared_key",Base64.getEncoder().encodeToString(new byte[32]));primary.getContentValues().put("proxy",1);
        backup.setName("Backup resolver");backup.setTopDomain("tunnel.example.com");backup.setEncrypted(false);backup.setPassword("demo-only");
        db.insert(primary.getContentValues());db.insert(backup.getContentValues());
        Activity main=null,editor=null;
        try {
            main=instrumentation.startActivitySync(new Intent(context,HomeActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));capture("01-PurpleHaze-Android-profili.png");
            editor=instrumentation.startActivitySync(new Intent(context,ProfileActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra(ProfileActivity.EXTRA_PROFILE_ID,primary.getId()));
            Activity target=editor;instrumentation.runOnMainSync(()->{target.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);target.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);target.getWindow().getDecorView().clearFocus();});
            capture("02-PurpleHaze-Android-profilo.png");
            instrumentation.runOnMainSync(()->scroll(target.getWindow().getDecorView()).smoothScrollTo(0,700));capture("03-PurpleHaze-Android-rete.png");
            instrumentation.runOnMainSync(()->scroll(target.getWindow().getDecorView()).fullScroll(View.FOCUS_DOWN));capture("04-PurpleHaze-Android-trasporto.png");
        } finally {
            if(editor!=null){Activity target=editor;instrumentation.runOnMainSync(()->{target.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);target.finish();});}
            if(main!=null){Activity target=main;instrumentation.runOnMainSync(target::finish);}
            db.delete(primary.getContentValues());db.delete(backup.getContentValues());db.close();
        }
    }
}
