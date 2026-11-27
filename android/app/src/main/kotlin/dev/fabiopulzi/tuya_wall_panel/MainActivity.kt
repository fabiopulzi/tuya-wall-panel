package dev.fabiopulzi.tuya_wall_panel

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Many Wi-Fi drivers drop broadcast packets unless an app holds this
        // lock, and Tuya devices announce their IP by UDP broadcast.
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("tuya-discovery").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "painel/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Window brightness: 0..1, or null to follow the system
                    // (including Android's adaptive brightness).
                    "setBrightness" -> {
                        val value = call.argument<Double>("value")
                        runOnUiThread {
                            val attrs = window.attributes
                            attrs.screenBrightness = value?.toFloat()
                                ?: android.view.WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = attrs
                        }
                        result.success(null)
                    }
                    "isDefaultHome" -> result.success(isDefaultHome())
                    "openHomeSettings" -> result.success(open(Settings.ACTION_HOME_SETTINGS))
                    "openDisplaySettings" -> result.success(open(Settings.ACTION_DISPLAY_SETTINGS))
                    "openSettings" -> result.success(open(Settings.ACTION_SETTINGS))
                    else -> result.notImplemented()
                }
            }
    }

    private fun isDefaultHome(): Boolean {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val info = packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
        return info?.activityInfo?.packageName == packageName
    }

    private fun open(action: String): Boolean = try {
        startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    override fun onDestroy() {
        multicastLock?.release()
        super.onDestroy()
    }
}
