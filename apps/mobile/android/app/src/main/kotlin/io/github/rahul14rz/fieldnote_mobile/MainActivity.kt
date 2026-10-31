package io.github.rahul14rz.fieldnote_mobile

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Android drops incoming multicast unless an app holds this lock, and
        // mDNS discovery of the gateway needs it while it browses.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fieldnote/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        multicastLock = (multicastLock ?: wifi.createMulticastLock("fieldnote-mdns")).apply {
                            setReferenceCounted(false)
                            acquire()
                        }
                        result.success(null)
                    }
                    "release" -> {
                        multicastLock?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
