package dev.vaani.keyboard;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import java.io.File;
import java.nio.file.Files;

/** Standalone disposable test editor. Java avoids the target APK's deduplicated
 * Kotlin runtime, which is unavailable when this test Activity runs separately. */
public class EditorFixtureActivity extends Activity {
    private AudioTrack playback;
    private LinearLayout root;
    private TextView status;
    private final Handler handler = new Handler(Looper.getMainLooper());
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL); root.setPadding(24, 24, 24, 24);
        TextView title = new TextView(this); title.setText("Vaani editor fixture · temporary text only"); root.addView(title);
        field("First editor", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        field("Second editor", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        field("Password editor", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        field("Number password editor", InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        status = new TextView(this); status.setText("Editor action: none");
        EditText done = field("Done action editor", InputType.TYPE_CLASS_TEXT);
        done.setSingleLine(true); done.setImeOptions(EditorInfo.IME_ACTION_DONE);
        done.setOnEditorActionListener((view, action, event) -> { status.setText("Editor action: " + action); return true; });
        root.addView(status);
        Button play = new Button(this); play.setText("Play synthetic Hinglish fixture");
        play.setOnClickListener(view -> playFixture()); root.addView(play);
        Button delayed = new Button(this); delayed.setText("Play fixture after 20 seconds");
        delayed.setOnClickListener(view -> {
            handler.removeCallbacksAndMessages(null);
            status.setText("Synthetic fixture scheduled in 20 seconds; switch to the editor to test.");
            handler.postDelayed(this::playFixture, 20000);
        }); root.addView(delayed);
        Button web = new Button(this); web.setText("Open offline web editors");
        web.setOnClickListener(view -> startActivity(new android.content.Intent(this, WebEditorFixtureActivity.class)));
        root.addView(web);
        setContentView(root);
    }
    private EditText field(String label, int type) {
        EditText field = new EditText(this); field.setHint(label); field.setContentDescription(label); field.setInputType(type);
        field.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO); field.setSaveEnabled(false); root.addView(field); return field;
    }
    private void playFixture() {
        try {
            if (playback != null) { playback.release(); playback = null; }
            File file = new File(getFilesDir(), "hinglish-fixture.pcm");
            if (file.length() < 2 || file.length() > 320000 || file.length() % 2 != 0) throw new Exception("Supply a PCM16 mono 16 kHz fixture of at most ten seconds.");
            byte[] pcm = Files.readAllBytes(file.toPath());
            AudioTrack track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(new AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STATIC).setBufferSizeInBytes(pcm.length).build();
            playback = track;
            if (track.write(pcm, 0, pcm.length) != pcm.length) throw new Exception("Fixture playback failed");
            track.play(); status.setText("Synthetic fixture playing");
            handler.postDelayed(() -> {
                if (playback == track) { playback = null; track.release(); status.setText("Synthetic fixture finished"); }
            }, pcm.length * 1000L / 32000 + 300);
        } catch (Exception error) {
            if (playback != null) { playback.release(); playback = null; }
            status.setText(error.getMessage());
        }
    }
    @Override public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (playback != null) { playback.release(); playback = null; }
        super.onDestroy();
    }
}
