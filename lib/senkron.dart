import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'db.dart';
import 'firebase_ayar.dart';

/// Telefonlar arası ortak veri: yerel SQLite ⇄ Firestore (firmalar/ana/<tablo>/<id>)
///
/// - Her yerel yazma 'degisiklik' tablosuna düşer, buradan Firestore'a gönderilir.
/// - Firestore'daki değişiklikler (_ts alanına göre) dinlenip yerel tabloya yazılır.
/// - Çevrimdışıyken Firestore yazmaları telefonda bekler, internet gelince gider.
class Senkron {
  static bool hazir = false; // Firebase başlatıldı mı
  static final durum = ValueNotifier<String>('kapali'); // kapali | bagli | gonderiyor | hata
  static final degisti = ValueNotifier<int>(0); // uzaktan veri gelince artar (ekranlar yenilenir)
  static String sonHata = '';
  static final _abonelik = <StreamSubscription>[];
  static final _kolonlar = <String, Set<String>>{};
  static bool _gonderiliyor = false, _tekrar = false;

  static Future<void> firebaseBaslat() async {
    if (!firebaseAyarli) return;
    try {
      await Firebase.initializeApp(options: firebaseSecenekleri);
      hazir = true;
    } catch (e) {
      sonHata = '$e';
      hazir = false;
    }
  }

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> _kol(String t) => _fs.collection('firmalar').doc(firmaKodu).collection(t);

  static Future<Set<String>> _kolon(String t) async {
    if (_kolonlar[t] != null) return _kolonlar[t]!;
    final r = await DB.q('PRAGMA table_info($t)');
    return _kolonlar[t] = r.map((e) => e['name'] as String).toSet();
  }

  /// Giriş yapıldıktan sonra çağrılır
  static String? _uid;
  static Future<void> baslat({bool zorla = false}) async {
    final u = hazir ? FirebaseAuth.instance.currentUser : null;
    if (u == null) return;
    if (!zorla && _uid == u.uid && _abonelik.isNotEmpty) return;
    durdur();
    _uid = u.uid;
    DB.degisti = gonder;
    durum.value = 'bagli';
    for (final t in DB.senkronTablolar) {
      final sonMs = int.tryParse(await DB.ayarOku('son_$t') ?? '') ?? 0;
      final sorgu = _kol(t).where('_ts', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(sonMs)).orderBy('_ts');
      _abonelik.add(sorgu.snapshots().listen((s) => _uygula(t, s), onError: (e) {
        sonHata = '$e';
        durum.value = 'hata';
      }));
    }
    unawaited(gonder());
  }

  static void durdur() {
    for (final a in _abonelik) {
      a.cancel();
    }
    _abonelik.clear();
    _uid = null;
    DB.degisti = null;
    durum.value = 'kapali';
  }

  static Future<void> _uygula(String t, QuerySnapshot<Map<String, dynamic>> s) async {
    if (s.docChanges.isEmpty) return;
    final kolon = await _kolon(t);
    final d = await DB.db;
    var enSon = 0, n = 0;
    await d.transaction((tx) async {
      for (final ch in s.docChanges) {
        final m = ch.doc.data();
        final id = int.tryParse(ch.doc.id);
        if (m == null || id == null) continue;
        final ts = m['_ts'];
        if (ts is Timestamp && ts.millisecondsSinceEpoch > enSon) enSon = ts.millisecondsSinceEpoch;
        // Bu cihazda gönderilmeyi bekleyen daha yeni bir değişiklik varsa onu ezme
        final bekleyen = await tx.query('degisiklik', columns: ['id'], where: 'tablo=? AND kayit_id=?', whereArgs: [t, id], limit: 1);
        if (bekleyen.isNotEmpty) continue;
        if (m['_sil'] == true || ch.type == DocumentChangeType.removed) {
          await tx.delete(t, where: 'id=?', whereArgs: [id]);
        } else {
          final satir = <String, Object?>{'id': id};
          m.forEach((k, v) {
            if (kolon.contains(k) && !k.startsWith('_')) satir[k] = v is Timestamp ? v.toDate().toIso8601String() : v;
          });
          await tx.insert(t, satir, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        n++;
      }
    });
    if (enSon > 0) {
      final eski = int.tryParse(await DB.ayarOku('son_$t') ?? '') ?? 0;
      if (enSon > eski) await DB.ayarYaz('son_$t', '$enSon');
    }
    if (n > 0) degisti.value++;
  }

  /// Bekleyen yerel değişiklikleri Firestore'a yazar
  static Future<void> gonder() async {
    if (!hazir || FirebaseAuth.instance.currentUser == null) return;
    if (_gonderiliyor) {
      _tekrar = true;
      return;
    }
    _gonderiliyor = true;
    durum.value = 'gonderiyor';
    try {
      do {
        _tekrar = false;
        while (true) {
          final l = await DB.q('SELECT * FROM degisiklik ORDER BY id LIMIT 400');
          if (l.isEmpty) break;
          final batch = _fs.batch();
          final islenen = <String>{};
          for (final c in l.reversed) {
            final t = c['tablo'] as String, id = c['kayit_id'] as int;
            if (!islenen.add('$t/$id')) continue; // aynı kaydın sadece son hali
            final ref = _kol(t).doc('$id');
            final satir = await DB.tek('SELECT * FROM $t WHERE id=?', [id]);
            if (satir == null) {
              batch.set(ref, {'_sil': true, '_ts': FieldValue.serverTimestamp()});
            } else {
              final veri = Map<String, dynamic>.from(satir)..remove('id');
              if (t == 'serbest_tablo' && '${veri['veri']}'.length > 900000) continue; // Firestore belge sınırı
              batch.set(ref, {...veri, '_sil': false, '_ts': FieldValue.serverTimestamp()});
            }
          }
          // Çevrimdışıyken commit internet gelene kadar beklediği için sonucu beklenmez; yazma telefonda kuyruğa alınır.
          unawaited(batch.commit().catchError((e) {
            sonHata = '$e';
            durum.value = 'hata';
          }));
          final sonId = l.last['id'] as int;
          final d = await DB.db;
          await d.delete('degisiklik', where: 'id<=?', whereArgs: [sonId]);
        }
      } while (_tekrar);
      if (durum.value != 'hata') durum.value = 'bagli';
    } catch (e) {
      sonHata = '$e';
      durum.value = 'hata';
    } finally {
      _gonderiliyor = false;
    }
  }

  /// Bu telefondaki tüm verileri (ilk kurulumda) buluta gönderilecek şekilde işaretler
  static Future<int> tumunuIsaretle() async {
    final d = await DB.db;
    var n = 0;
    await d.transaction((tx) async {
      for (final t in DB.senkronTablolar) {
        final r = await tx.query(t, columns: ['id']);
        for (final x in r) {
          await tx.insert('degisiklik', {'tablo': t, 'kayit_id': x['id'], 'sil': 0});
          n++;
        }
      }
    });
    unawaited(gonder());
    return n;
  }
}
