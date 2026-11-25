package local.piliaurora.audiofocusfixture;

import android.app.Activity;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

public final class FocusActivity extends Activity {
    private boolean requested;

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (!hasFocus || requested) return;
        requested = true;
        AudioManager audio = getSystemService(AudioManager.class);
        AudioFocusRequest request = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build())
            .setOnAudioFocusChangeListener(change -> Log.i("PiliFocusFixture", "change=" + change))
            .build();
        int result = audio.requestAudioFocus(request);
        Log.i("PiliFocusFixture", "request=" + result);
        new Handler(Looper.getMainLooper()).postDelayed(() -> moveTaskToBack(true), 500);
    }
}
