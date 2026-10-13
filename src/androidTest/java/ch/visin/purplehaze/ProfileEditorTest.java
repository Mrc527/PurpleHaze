package ch.visin.purplehaze;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import ch.visin.purplehaze.config.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.util.Base64;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class ProfileEditorTest {
    private final Instrumentation instrumentation=InstrumentationRegistry.getInstrumentation();
    private final Context context=instrumentation.getTargetContext();
    private Button button(View view,String text){if(view instanceof Button&&text.contentEquals(((Button)view).getText()))return(Button)view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){Button result=button(((ViewGroup)view).getChildAt(i),text);if(result!=null)return result;}return null;}
    private EditText field(Activity activity,String tag){return activity.getWindow().getDecorView().findViewWithTag(tag);}
    private Activity editor(){return instrumentation.startActivitySync(new Intent(context,ProfileActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));}
    @Test public void saveCreatesOnlyRequestedProfileAndKeepsSecretWindowProtected() {
        Activity activity=editor();ProfileRepository db=new ProfileRepository(context);ConnectionProfile saved=null;
        String name="UI save "+System.nanoTime(), key=Base64.getEncoder().encodeToString(new byte[32]);
        try {
            assertTrue((activity.getWindow().getAttributes().flags&WindowManager.LayoutParams.FLAG_SECURE)!=0);
            instrumentation.runOnMainSync(()->{field(activity,"name").setText(name);field(activity,"domain").setText("ui.example.com");field(activity,"key").setText(key);button(activity.getWindow().getDecorView(),"Save profile").performClick();});
            instrumentation.waitForIdleSync();
            for(ConnectionProfile profile:db.selectAll())if(name.equals(profile.getName()))saved=db.selectById(profile.getId());
            assertNotNull(saved);assertTrue(saved.isEncrypted());assertEquals(key,saved.getSharedKey());assertEquals("ui.example.com",saved.getTopDomain());
        } finally {if(saved!=null)db.delete(saved.getContentValues());db.close();instrumentation.runOnMainSync(activity::finish);}
    }
    @Test public void rotationKeepsUnsavedDraftWithoutWritingCredentialsToDatabase() throws Exception {
        Activity initial=editor();Activity rotated=null;ProfileRepository db=new ProfileRepository(context);
        String name="Unsaved "+System.nanoTime(), key=Base64.getEncoder().encodeToString(new byte[32]);
        Instrumentation.ActivityMonitor monitor=instrumentation.addMonitor(ProfileActivity.class.getName(),null,false);
        try {
            instrumentation.runOnMainSync(()->{field(initial,"name").setText(name);field(initial,"key").setText(key);initial.recreate();});
            rotated=instrumentation.waitForMonitorWithTimeout(monitor,10000);assertNotNull("Editor did not recreate",rotated);instrumentation.waitForIdleSync();
            Activity current=rotated;instrumentation.runOnMainSync(()->{assertEquals(name,field(current,"name").getText().toString());assertEquals(key,field(current,"key").getText().toString());});
            assertTrue((rotated.getWindow().getAttributes().flags&WindowManager.LayoutParams.FLAG_SECURE)!=0);
            assertFalse(db.selectAll().stream().anyMatch(p->name.equals(p.getName())));
        } finally {instrumentation.removeMonitor(monitor);if(rotated!=null){Activity current=rotated;instrumentation.runOnMainSync(current::finish);}instrumentation.runOnMainSync(initial::finish);db.close();}
    }
}
