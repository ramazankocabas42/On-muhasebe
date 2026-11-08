package com.kones.on_muhasebe

import android.app.Notification
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.io.File

/** Takip edilen WhatsApp sohbetlerinden gelen bildirimleri dosyaya kaydeder (uygulama kapalıyken de çalışır). */
class WaDinleyici : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            if (sbn.packageName != "com.whatsapp" && sbn.packageName != "com.whatsapp.w4b") return
            val n = sbn.notification ?: return
            if ((n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
            val ex = n.extras ?: return
            val baslik = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return
            val konusma = ex.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
            val sohbet = WaDepo.temizAd(konusma ?: baslik)
            if (sohbet.isEmpty() || sohbet == "WhatsApp") return
            WaDepo.gorulenEkle(this, sohbet)
            if (!WaDepo.takipOku(this).contains(sohbet)) return
            @Suppress("DEPRECATION")
            val mesajlar = ex.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (mesajlar != null && mesajlar.isNotEmpty()) {
                for (p in mesajlar) {
                    val b = p as? Bundle ?: continue
                    val metin = b.getCharSequence("text")?.toString() ?: continue
                    var gonderen = b.getCharSequence("sender")?.toString()
                    if (gonderen == null && Build.VERSION.SDK_INT >= 28) {
                        @Suppress("DEPRECATION")
                        val kisi = b.getParcelable<android.app.Person>("sender_person")
                        gonderen = kisi?.name?.toString()
                    }
                    if (gonderen == null) gonderen = if (konusma == null) baslik else ""
                    WaDepo.ekle(this, sohbet, gonderen, metin, b.getLong("time", sbn.postTime))
                }
            } else {
                val metin = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: return
                WaDepo.ekle(this, sohbet, if (konusma == null) baslik else "", metin, sbn.postTime)
            }
        } catch (e: Exception) {
        }
    }
}

object WaDepo {
    private const val PREF = "wa_ayar"
    private const val DOSYA = "wa_bildirim.jsonl"
    private val kilit = Any()

    fun temizAd(s: String): String = s.replace(Regex("\\s*\\(\\d+[^)]*\\)\\s*$"), "").trim()

    fun takipOku(c: Context): Set<String> =
        c.getSharedPreferences(PREF, Context.MODE_PRIVATE).getStringSet("takip", emptySet()) ?: emptySet()

    fun takipYaz(c: Context, l: List<String>) {
        c.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putStringSet("takip", l.toSet()).apply()
    }

    fun gorulenOku(c: Context): Set<String> =
        c.getSharedPreferences(PREF, Context.MODE_PRIVATE).getStringSet("gorulen", emptySet()) ?: emptySet()

    fun gorulenEkle(c: Context, ad: String) {
        val p = c.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val s = (p.getStringSet("gorulen", emptySet()) ?: emptySet()).toMutableSet()
        if (s.add(ad)) {
            if (s.size > 200) s.remove(s.first())
            p.edit().putStringSet("gorulen", s).apply()
        }
    }

    fun ekle(c: Context, sohbet: String, gonderen: String, metin: String, zaman: Long) {
        synchronized(kilit) {
            val anahtar = "$sohbet|$gonderen|$zaman|$metin"
            val p = c.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            val son = (p.getString("son", "") ?: "").split("\n").toMutableList()
            val h = anahtar.hashCode().toString()
            if (son.contains(h)) return
            son.add(h)
            while (son.size > 500) son.removeAt(0)
            p.edit().putString("son", son.joinToString("\n")).apply()
            val j = JSONObject()
            j.put("sohbet", sohbet); j.put("kisi", gonderen); j.put("metin", metin); j.put("zaman", zaman)
            File(c.filesDir, DOSYA).appendText(j.toString().replace("\n", "\\n") + "\n")
        }
    }

    fun oku(c: Context): String = synchronized(kilit) {
        val f = File(c.filesDir, DOSYA)
        if (f.exists()) f.readText() else ""
    }

    /** İşlenen ilk [adet] satırı siler */
    fun temizle(c: Context, adet: Int) = synchronized(kilit) {
        val f = File(c.filesDir, DOSYA)
        if (!f.exists()) return@synchronized
        val kalan = f.readLines().filter { it.isNotBlank() }.drop(adet)
        f.writeText(if (kalan.isEmpty()) "" else kalan.joinToString("\n") + "\n")
    }
}
