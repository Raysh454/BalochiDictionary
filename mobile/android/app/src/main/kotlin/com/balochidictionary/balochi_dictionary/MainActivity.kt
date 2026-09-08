package com.balochidictionary.balochi_dictionary

import android.os.Bundle
import com.balochidictionary.balochi_dictionary.widget.WidgetRefresher
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Opening the app is the one moment the Rekhta fetch is guaranteed to
        // be allowed: a foreground process is never denied the network, and is
        // never subject to the power management that can stop the widget's own
        // background refresh from running at all. Cheap, and it means the
        // widgets are never stuck waiting on a background job that a
        // restrictive phone will not run.
        WidgetRefresher.refreshAsync(this)
    }
}
