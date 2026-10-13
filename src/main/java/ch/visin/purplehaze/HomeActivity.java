package ch.visin.purplehaze;

import android.app.*;
import android.content.*;
import android.os.*;
import android.widget.*;
import ch.visin.purplehaze.config.*;
import java.util.List;

/** Profile dashboard. Tunnel lifecycle remains owned by TunnelService. */
public class HomeActivity extends Activity {
    private ProfileRepository repository;
    private LinearLayout content;
    private String status=TunnelService.ACTION_STATUS_IDLE;
    private Long activeId,pendingId;
    private TextView logView;
    private final BroadcastReceiver updates=new BroadcastReceiver(){public void onReceive(Context c,Intent i){
        if(NativeTunnel.ACTION_LOG_MESSAGE.equals(i.getAction())){if(logView!=null)logView.append(i.getStringExtra(NativeTunnel.EXTRA_MESSAGE)+"\n");return;}
        status=i.getAction();long id=i.getLongExtra(TunnelService.EXTRA_CONFIGURATION_ID,-1);activeId=id<0?null:id;
        render();
        if(TunnelService.ACTION_STATUS_ERROR.equals(status))new AlertDialog.Builder(HomeActivity.this).setTitle("Connection failed").setMessage(i.getStringExtra(TunnelService.EXTRA_ERROR_MESSAGE)).setPositiveButton("OK",null).show();
    }};
    @Override public void onCreate(Bundle b){super.onCreate(b);if(b!=null&&b.containsKey("pending_profile"))pendingId=b.getLong("pending_profile");repository=new ProfileRepository(this);
        if(Build.VERSION.SDK_INT>=33&&checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},602);
    }
    @Override protected void onSaveInstanceState(Bundle out){super.onSaveInstanceState(out);if(pendingId!=null)out.putLong("pending_profile",pendingId);}
    @Override protected void onStart(){super.onStart();IntentFilter f=new IntentFilter();
        for(String a:new String[]{TunnelService.ACTION_STATUS_IDLE,TunnelService.ACTION_STATUS_CONNECT,TunnelService.ACTION_STATUS_CONNECTED,TunnelService.ACTION_STATUS_DISCONNECT,TunnelService.ACTION_STATUS_ERROR,NativeTunnel.ACTION_LOG_MESSAGE})f.addAction(a);
        AppBroadcasts.register(this,updates,f);
        TunnelService s=TunnelService.instance;if(s!=null){status=s.getStatus();activeId=s.getProfileId();}else{status=TunnelService.ACTION_STATUS_IDLE;activeId=null;}
        render();startService(new Intent(this,TunnelService.class).setAction(TunnelService.ACTION_CONTROL_UPDATE));
    }
    @Override protected void onStop(){unregisterReceiver(updates);super.onStop();}
    @Override protected void onDestroy(){repository.close();super.onDestroy();}
    private boolean busy(){return TunnelService.instance!=null&&TunnelService.instance.isBusy();}
    private long selected(){return getPreferences(MODE_PRIVATE).getLong("selected_profile",-1);}
    private void select(long id){getPreferences(MODE_PRIVATE).edit().putLong("selected_profile",id).apply();render();}
    private void render(){
        content=Brand.screen(this,"PurpleHaze",null);
        content.addView(Brand.text(this,"Your connection, through DNS.",15,Brand.MUTED,false));Brand.gap(content,16);
        try{
            List<ConnectionProfile> profiles=repository.selectAll();ConnectionProfile chosen=null;
            for(ConnectionProfile p:profiles)if(p.getId()==(busy()&&activeId!=null?activeId:selected()))chosen=p;
            if(chosen==null&&!profiles.isEmpty()){chosen=profiles.get(0);getPreferences(MODE_PRIVATE).edit().putLong("selected_profile",chosen.getId()).apply();}
            LinearLayout connection=Brand.card(content);
            String state=TunnelService.ACTION_STATUS_CONNECTED.equals(status)?"Connected":TunnelService.ACTION_STATUS_CONNECT.equals(status)?"Connecting…":TunnelService.ACTION_STATUS_DISCONNECT.equals(status)?"Disconnecting…":"Disconnected";
            connection.addView(Brand.text(this,state,24,Brand.PURPLE,true));
            connection.addView(Brand.text(this,chosen==null?"Create a profile to get started.":chosen.getName()+"\n"+chosen.getTopDomain(),16,Brand.INK,false));
            if(chosen!=null){connection.addView(Brand.text(this,(chosen.isEncrypted()?"Encrypted":"Legacy · unencrypted")+(chosen.getProxy()?" · TCP / UDP / DNS proxy":""),13,Brand.MUTED,false));}
            final ConnectionProfile target=chosen;
            Button connect=Brand.button(this,busy()?"Disconnect":"Connect",true,()->{if(busy())sendBroadcast(new Intent(TunnelService.ACTION_CONTROL_DISCONNECT).setPackage(getPackageName()));else if(target!=null)connect(target.getId());});
            connect.setEnabled(chosen!=null);connection.addView(connect);
            LinearLayout row=new LinearLayout(this);row.setGravity(android.view.Gravity.CENTER_VERTICAL);
            row.addView(Brand.text(this,"Profiles",21,Brand.INK,true),new LinearLayout.LayoutParams(0,-2,1));
            Button add=Brand.button(this,"+ New",false,()->edit(-1));add.setEnabled(!busy());row.addView(add);content.addView(row);Brand.gap(content,12);
            for(ConnectionProfile p:profiles){LinearLayout card=Brand.card(content);
                card.addView(Brand.text(this,p.getName()+(p.getId()==selected()?"  ✓":""),18,Brand.INK,true));
                card.addView(Brand.text(this,p.getTopDomain(),15,Brand.MUTED,false));
                card.addView(Brand.text(this,p.isEncrypted()?(p.getProxy()?"Encrypted · Server proxy":"Encrypted tunnel"):"Legacy tunnel",13,Brand.PURPLE,false));
                LinearLayout buttons=new LinearLayout(this);
                Button use=Brand.button(this,p.getId()==selected()?"Selected":"Select",false,()->select(p.getId()));use.setEnabled(!busy()&&p.getId()!=selected());buttons.addView(use,new LinearLayout.LayoutParams(0,-2,1));
                Button edit=Brand.button(this,"Edit",false,()->edit(p.getId()));edit.setEnabled(!busy());buttons.addView(edit,new LinearLayout.LayoutParams(0,-2,1));card.addView(buttons);
            }
            if(busy())content.addView(Brand.text(this,"Disconnect before changing profiles.",13,Brand.MUTED,false));
            content.addView(Brand.button(this,"Connection log",false,this::showLog));
            content.addView(Brand.button(this,"About PurpleHaze",false,this::about));
        }catch(Exception e){content.addView(Brand.text(this,e.getMessage(),16,Brand.PURPLE,false));}
    }
    private void edit(long id){if(!busy())startActivity(new Intent(this,ProfileActivity.class).putExtra(ProfileActivity.EXTRA_PROFILE_ID,id));}
    private void connect(long id){pendingId=id;Intent consent=android.net.VpnService.prepare(this);if(consent!=null)startActivityForResult(consent,602);else startTunnel();}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==602&&result==RESULT_OK)startTunnel();}
    private void startTunnel(){if(pendingId!=null)startForegroundService(new Intent(this,TunnelService.class).setAction(TunnelService.ACTION_CONTROL_CONNECT).putExtra(TunnelService.EXTRA_CONFIGURATION_ID,pendingId.longValue()));}
    private void showLog(){logView=Brand.text(this,TunnelService.instance==null?"No connection log yet.":TunnelService.instance.getLog(),12,Brand.INK,false);logView.setTypeface(android.graphics.Typeface.MONOSPACE);logView.setTextIsSelectable(true);ScrollView scroll=new ScrollView(this);scroll.addView(logView);new AlertDialog.Builder(this).setTitle("Connection log").setView(scroll).setPositiveButton("Close",null).setOnDismissListener(d->logView=null).show();}
    private void about(){try(java.io.InputStream stream=getResources().openRawResource(R.raw.license);java.util.Scanner scanner=new java.util.Scanner(stream).useDelimiter("\\A")){new AlertDialog.Builder(this).setTitle("PurpleHaze · Android").setMessage("Encrypted iodine 0x602\nBased on AndIodine and PurpleHaze.\n\n"+scanner.next()).setPositiveButton("Close",null).show();}catch(Exception e){Brand.error(this,e);}}
}
