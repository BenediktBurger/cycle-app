package io.github.benediktburger.cycleapp

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // In release builds cycle data (diary text, temperatures) must not leak
    // into screenshots, screen recordings, or the recents task snapshot:
    // with FLAG_SECURE the window's surface is unreadable to any capturer,
    // so all of them render the scrim. The flag stays set for the whole
    // lifetime of the release window — clearing it only while backgrounded
    // would still leak, because the snapshot is taken after the window
    // stops being visible. Debug builds stay capturable (test/demo phase:
    // testers send annotated screenshots).
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.DEBUG) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
    }

    override fun onResume() {
        super.onResume()
        if (!BuildConfig.DEBUG) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
    }
}
