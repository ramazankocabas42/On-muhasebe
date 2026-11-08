package com.kones.on_muhasebe

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kones/wa").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "izinVarMi" -> {
                        val s = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
                        result.success(s.contains(ComponentName(this, WaDinleyici::class.java).flattenToString()))
                    }
                    "izinAc" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "takipOku" -> result.success(WaDepo.takipOku(this).toList())
                    "takipAyarla" -> {
                        WaDepo.takipYaz(this, call.argument<List<String>>("liste") ?: listOf())
                        result.success(true)
                    }
                    "gorulenler" -> result.success(WaDepo.gorulenOku(this).toList())
                    "oku" -> result.success(WaDepo.oku(this))
                    "temizle" -> {
                        WaDepo.temizle(this, call.argument<Int>("adet") ?: 0)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("hata", e.message, null)
            }
        }
    }
}
