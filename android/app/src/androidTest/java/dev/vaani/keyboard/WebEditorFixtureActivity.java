package dev.vaani.keyboard;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;

/** Test APK only: disposable offline web inputs, no scripts, network or saved form data. */
public class WebEditorFixtureActivity extends Activity {
    private WebView web;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        web.getSettings().setBlockNetworkLoads(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(false);
        web.loadDataWithBaseURL("https://fixture.invalid/", "<!doctype html><html lang='en'>"
            + "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            + "<style>body{font:18px sans-serif;padding:12px}textarea,input,[contenteditable]{box-sizing:border-box;width:100%;font:20px sans-serif;margin:8px 0;padding:10px;border:1px solid #777;min-height:60px}</style>"
            + "<h3>Vaani offline web editor fixture</h3>"
            + "<label>Web textarea<textarea aria-label='Web textarea' autocomplete='off'></textarea></label>"
            + "<div>Rich text editor</div><div role='textbox' aria-label='Rich text editor' contenteditable='true'></div>"
            + "<label>Web password<input aria-label='Web password' type='password' autocomplete='off'></label>"
            + "<p>Temporary synthetic text only. Nothing is submitted or saved.</p></html>", "text/html", "UTF-8", null);
        setContentView(web);
    }
    @Override public void onDestroy() {
        web.destroy();
        super.onDestroy();
    }
}
