package ch.visin.purplehaze;

import android.app.*;
import android.os.Bundle;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import ch.visin.purplehaze.config.*;
import java.util.*;

/** Explicit Save/Cancel keeps incomplete edits out of stored connection profiles. */
public class ProfileActivity extends Activity {
    public static final String EXTRA_PROFILE_ID="profile_id";
    private ProfileRepository repository;
    private ConnectionProfile profile;
    private final Map<String,EditText> fields=new HashMap<>();
    private Switch proxy,raw,lazy,route,ipv6;
    private Spinner dnsMode,type,encoding,securityMode;
    private static class Draft { Map<String,String> text=new HashMap<>(); boolean[] switches; int[] choices; }
    @Override public void onCreate(Bundle saved){super.onCreate(saved);getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        repository=new ProfileRepository(this);
        if(TunnelService.instance!=null&&TunnelService.instance.isBusy()){finish();return;}
        try{long id=getIntent().getLongExtra(EXTRA_PROFILE_ID,-1);profile=id<0?ConnectionProfile.create():repository.selectById(id);if(profile==null)throw new IllegalStateException("Profile no longer exists");build();restoreDraft();}catch(Exception e){new AlertDialog.Builder(this).setTitle("Cannot open profile").setMessage(e.getMessage()).setPositiveButton("Close",(d,w)->finish()).show();}
    }
    private LinearLayout section(LinearLayout parent,String title,String detail){LinearLayout card=Brand.card(parent);card.addView(Brand.text(this,title,20,Brand.INK,true));if(detail!=null)card.addView(Brand.text(this,detail,13,Brand.MUTED,false));return card;}
    private void field(LinearLayout parent,String id,String label,String value,String hint,boolean secret,boolean number){parent.addView(Brand.text(this,label,14,Brand.MUTED,true));EditText e=new EditText(this);e.setTag(id);e.setContentDescription(label);e.setTextSize(16);e.setTextColor(Brand.INK);e.setSingleLine();e.setText(value);e.setHint(hint);e.setMinHeight(Brand.dp(this,48));
        e.setInputType(number?InputType.TYPE_CLASS_NUMBER:InputType.TYPE_CLASS_TEXT|(secret?InputType.TYPE_TEXT_VARIATION_PASSWORD:InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS));
        e.setSaveEnabled(false);e.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);fields.put(id,e);parent.addView(e);Brand.gap(parent,8);}
    private Switch toggle(LinearLayout parent,String label,boolean checked){Switch v=new Switch(this);v.setText(label);v.setTextSize(16);v.setTextColor(Brand.INK);v.setMinHeight(Brand.dp(this,52));v.setChecked(checked);parent.addView(v);return v;}
    private Spinner choice(LinearLayout parent,String label,String[] values,int index){parent.addView(Brand.text(this,label,14,Brand.MUTED,true));Spinner s=new Spinner(this);s.setContentDescription(label);ArrayAdapter<String>a=new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,values);s.setAdapter(a);s.setSelection(Math.max(0,index));s.setMinimumHeight(Brand.dp(this,48));parent.addView(s);return s;}
    private void build(){LinearLayout body=Brand.screen(this,profile.getId()==null?"New profile":"Edit profile",this::cancel);
        LinearLayout general=section(body,"Profile",null);
        field(general,"name","Name",profile.getName(),"Home server",false,false);field(general,"domain","Top domain",profile.getTopDomain(),"tunnel.example.com",false,false);
        LinearLayout security=section(body,"Security","Use a 32-byte shared key in Base64. Select Legacy only for servers using the original unencrypted protocol.");
        securityMode=choice(security,"Connection security",new String[]{"Encrypted · iodine 0x602","Legacy · unencrypted 0x502"},profile.isEncrypted()?0:1);
        field(security,"key","Shared key · Base64",profile.getSharedKey(),"Server key",true,false);
        field(security,"password","Legacy password",profile.getPassword(),"Used in Legacy mode",true,false);
        proxy=toggle(security,"Server proxy · TCP / UDP / DNS",profile.getProxy());
        securityMode.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){public void onNothingSelected(android.widget.AdapterView<?> p){}public void onItemSelected(android.widget.AdapterView<?> p,View v,int position,long id){updateSecurity();}});
        security.addView(Brand.text(this,"Proxy mode requires encryption and sends IPv4 app traffic through your server. IPv6 traffic is blocked.",13,Brand.MUTED,false));
        LinearLayout network=section(body,"Routing & DNS",null);
        route=toggle(network,"Route all IPv4 traffic",profile.getDefaultRoute());network.addView(Brand.text(this,"Always enabled while Server proxy is on.",13,Brand.MUTED,false));
        dnsMode=choice(network,"DNS inside the tunnel",new String[]{"System default","Tunnel server","Custom DNS"},profile.getNameserverMode().ordinal());
        field(network,"dns","Custom DNS",profile.getNameserver(),"1.1.1.1",false,false);
        LinearLayout transport=section(body,"Transport","These settings control how the DNS tunnel reaches your server.");
        field(transport,"resolver","Tunnel nameserver",profile.getTunnelNameserver(),"Automatic",false,false);
        ipv6=toggle(transport,"Allow IPv6 tunnel nameservers",profile.getIpv6Transport());
        raw=toggle(transport,"Try direct UDP",profile.getRawMode());lazy=toggle(transport,"Lazy mode",profile.getLazyMode());
        type=choice(transport,"DNS query type",new String[]{"Automatic","NULL","PRIVATE","TXT","SRV","MX","CNAME","A"},profile.getRequestType().ordinal());
        String[] enc={"Automatic","base32","base64","base64u","base128","raw"};encoding=choice(transport,"Downstream encoding",enc,Arrays.asList(enc).indexOf(profile.getDownstreamEncoding()));
        field(transport,"timeout","Request timeout · seconds",Integer.toString(profile.getRequestTimeout()),"1",false,true);
        field(transport,"hostname","Maximum hostname length",Integer.toString(profile.getRequestHostnameSize()),"255",false,true);
        field(transport,"fragment","Downstream fragment size · 0 = automatic",Integer.toString(profile.getResponseFragmentSize()),"0",false,true);
        body.addView(Brand.button(this,"Save profile",true,this::save));
        if(profile.getId()!=null)body.addView(Brand.button(this,"Delete profile",false,()->new AlertDialog.Builder(this).setTitle("Delete "+profile.getName()+"?").setMessage("This removes the profile and its stored credentials.").setNegativeButton("Cancel",null).setPositiveButton("Delete",(d,w)->{repository.delete(profile.getContentValues());finish();}).show()));
    }
    private void updateSecurity(){boolean encrypted=securityMode.getSelectedItemPosition()==0;fields.get("key").setEnabled(encrypted);fields.get("password").setEnabled(!encrypted);proxy.setEnabled(encrypted);}
    @Override public Object onRetainNonConfigurationInstance(){
        if(profile==null||securityMode==null)return null;
        Draft draft=new Draft();for(Map.Entry<String,EditText> e:fields.entrySet())draft.text.put(e.getKey(),e.getValue().getText().toString());
        draft.switches=new boolean[]{proxy.isChecked(),raw.isChecked(),lazy.isChecked(),route.isChecked(),ipv6.isChecked()};
        draft.choices=new int[]{securityMode.getSelectedItemPosition(),dnsMode.getSelectedItemPosition(),type.getSelectedItemPosition(),encoding.getSelectedItemPosition()};return draft;
    }
    private void restoreDraft(){
        Draft draft=(Draft)getLastNonConfigurationInstance();if(draft==null)return;
        for(Map.Entry<String,String> e:draft.text.entrySet())fields.get(e.getKey()).setText(e.getValue());
        Switch[] switches={proxy,raw,lazy,route,ipv6};for(int i=0;i<switches.length;i++)switches[i].setChecked(draft.switches[i]);
        Spinner[] choices={securityMode,dnsMode,type,encoding};for(int i=0;i<choices.length;i++)choices[i].setSelection(draft.choices[i]);
        updateSecurity();
    }
    private String value(String id){return fields.get(id).getText().toString().trim();}
    private int number(String id,int min,int max){int x;try{x=Integer.parseInt(value(id));}catch(NumberFormatException e){throw new IllegalArgumentException("Enter a valid number for "+id);}if(x<min||x>max)throw new IllegalArgumentException(id+" must be between "+min+" and "+max);return x;}
    private void save(){try{
        if(TunnelService.instance!=null&&TunnelService.instance.isBusy())throw new IllegalStateException("Disconnect before editing profiles");
        if(value("name").isEmpty()||value("domain").isEmpty())throw new IllegalArgumentException("Enter a profile name and top domain");
        boolean encrypted=securityMode.getSelectedItemPosition()==0;
        String password=encrypted?"":fields.get("password").getText().toString();String sharedKey=encrypted?value("key"):"";
        if(encrypted&&sharedKey.isEmpty())throw new IllegalArgumentException("Enter the shared key for an encrypted connection");
        byte[] key=SharedKey.validate(sharedKey,password,encrypted&&proxy.isChecked());if(key!=null)Arrays.fill(key,(byte)0);
        if(password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>32)throw new IllegalArgumentException("Legacy passwords support at most 32 UTF-8 bytes");
        if(dnsMode.getSelectedItemPosition()==2&&value("dns").isEmpty())throw new IllegalArgumentException("Enter a custom DNS server");
        profile.setEncrypted(encrypted);profile.setName(value("name"));profile.setTopDomain(value("domain"));profile.setPassword(password);profile.getContentValues().put(ProfileRepository.COLUMN_CONF_SHARED_KEY,sharedKey);profile.getContentValues().put(ProfileRepository.COLUMN_CONF_PROXY,encrypted&&proxy.isChecked()?1:0);
        profile.setDefaultRoute(route.isChecked());profile.setNameserverMode(ConnectionProfile.NameserverMode.values()[dnsMode.getSelectedItemPosition()]);profile.setNameserver(value("dns"));profile.setTunnelNameserver(value("resolver"));profile.setIpv6Transport(ipv6.isChecked());profile.setRawMode(raw.isChecked());profile.setLazyMode(lazy.isChecked());profile.setRequestType(ConnectionProfile.RequestType.values()[type.getSelectedItemPosition()]);profile.setDownstreamEncoding(encoding.getSelectedItemPosition()==0?"":encoding.getSelectedItem().toString());profile.setRequestTimeout(number("timeout",1,60));profile.setRequestHostnameSize(number("hostname",100,255));profile.setResponseFragmentSize(number("fragment",0,65535));
        repository.insertOrUpdate(profile.getContentValues());finish();
    }catch(Exception e){Brand.error(this,e);}}
    private void cancel(){new AlertDialog.Builder(this).setTitle("Discard changes?").setNegativeButton("Keep editing",null).setPositiveButton("Discard",(d,w)->finish()).show();}
    @Override public void onBackPressed(){cancel();}
    @Override protected void onDestroy(){if(repository!=null)repository.close();for(EditText e:fields.values())e.setText("");super.onDestroy();}
}
