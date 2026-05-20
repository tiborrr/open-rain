package com.casteleijn.openrain

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Equivalent to enableEdgeToEdge() on androidx.core 1.15 (Flutter's pin).
        // Transparent system bars are set in styles.xml; API 35+ enforces edge-to-edge.
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
