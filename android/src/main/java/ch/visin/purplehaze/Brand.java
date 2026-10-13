package ch.visin.purplehaze;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.view.View;
import android.view.WindowInsets;
import android.widget.*;

/** Shared PurpleHaze palette, spacing and native controls. */
public final class Brand {
    public static final int PURPLE=Color.rgb(115,25,99), INK=Color.rgb(37,22,46), MUTED=Color.rgb(110,94,118), BACK=Color.rgb(250,245,253), LAVENDER=Color.rgb(228,193,249);
    private Brand() {}
    public static int dp(android.content.Context c, int n) { return Math.round(n*c.getResources().getDisplayMetrics().density); }
    public static GradientDrawable shape(int color, int radius, android.content.Context c) {
        GradientDrawable d=new GradientDrawable(); d.setColor(color);d.setCornerRadius(dp(c,radius));return d;
    }
    public static LinearLayout column(android.content.Context c) { LinearLayout v=new LinearLayout(c);v.setOrientation(LinearLayout.VERTICAL);return v; }
    public static TextView text(android.content.Context c,String s,int size,int color,boolean bold) {
        TextView v=new TextView(c);v.setText(s);v.setTextSize(size);v.setTextColor(color);
        if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(0,dp(c,4),0,dp(c,4));return v;
    }
    public static void gap(LinearLayout parent,int n) { View v=new View(parent.getContext());parent.addView(v,new LinearLayout.LayoutParams(1,dp(parent.getContext(),n))); }
    public static Button button(android.content.Context c,String title,boolean primary,Runnable action) {
        Button b=new Button(c);b.setText(title);b.setAllCaps(false);b.setTextSize(16);b.setTextColor(primary?Color.WHITE:PURPLE);
        b.setBackgroundTintList(ColorStateList.valueOf(primary?PURPLE:Color.rgb(242,226,250)));
        b.setMinHeight(dp(c,48));b.setOnClickListener(v->action.run());return b;
    }
    public static LinearLayout card(LinearLayout parent) {
        LinearLayout c=column(parent.getContext()); c.setPadding(dp(c.getContext(),18),dp(c.getContext(),14),dp(c.getContext(),18),dp(c.getContext(),14));
        c.setBackground(shape(Color.WHITE,18,c.getContext()));
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=dp(c.getContext(),14);parent.addView(c,p);return c;
    }
    public static LinearLayout screen(Activity a,String title,Runnable back) {
        a.getWindow().setStatusBarColor(BACK);a.getWindow().setNavigationBarColor(BACK);
        a.getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|(Build.VERSION.SDK_INT>=27?View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR:0));
        if(Build.VERSION.SDK_INT>=30)a.getWindow().setDecorFitsSystemWindows(false);
        LinearLayout root=column(a);root.setBackgroundColor(BACK);
        root.setOnApplyWindowInsetsListener((v,insets)->{
            int left,top,right,bottom;
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets i=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout()|WindowInsets.Type.ime());left=i.left;top=i.top;right=i.right;bottom=i.bottom;}
            else{left=insets.getSystemWindowInsetLeft();top=insets.getSystemWindowInsetTop();right=insets.getSystemWindowInsetRight();bottom=insets.getSystemWindowInsetBottom();}
            v.setPadding(dp(a,20)+left,top+dp(a,12),dp(a,20)+right,bottom);return insets;
        });
        LinearLayout header=new LinearLayout(a);header.setGravity(android.view.Gravity.CENTER_VERTICAL);
        if(back!=null){Button b=button(a,"‹ Back",false,back);header.addView(b,new LinearLayout.LayoutParams(dp(a,88),dp(a,48)));}
        else{ImageView icon=new ImageView(a);icon.setImageResource(R.drawable.purple_haze);header.addView(icon,new LinearLayout.LayoutParams(dp(a,40),dp(a,40)));}
        TextView heading=text(a,title,26,INK,true);heading.setPadding(dp(a,12),0,0,0);header.addView(heading,new LinearLayout.LayoutParams(0,-2,1));root.addView(header);
        gap(root,16);ScrollView scroll=new ScrollView(a);scroll.setFillViewport(true);scroll.setClipToPadding(false);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout content=column(a);content.setFocusableInTouchMode(true);content.setPadding(0,0,0,dp(a,20));scroll.addView(content,new ScrollView.LayoutParams(-1,-2));a.setContentView(root);root.requestApplyInsets();return content;
    }
    public static void error(Activity a,Exception e){new android.app.AlertDialog.Builder(a).setTitle("Unable to continue").setMessage(e.getMessage()).setPositiveButton("OK",null).show();}
}
