import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'db.dart';
import 'ortak.dart';
import 'whatsapp.dart';

/// Android tarafındaki WhatsApp bildirim dinleyicisiyle konuşur.
class WaKanal {
  static const _k = MethodChannel('kones/wa');

  static Future<bool> izinVarMi() async {
    try {
      return await _k.invokeMethod<bool>('izinVarMi') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> izinAc() async {
    try {
      await _k.invokeMethod('izinAc');
    } catch (_) {}
  }

  static Future<List<String>> _liste(String m) async {
    try {
      return ((await _k.invokeMethod<List>(m)) ?? []).map((e) => '$e').toList()..sort();
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> takip() => _liste('takipOku');
  static Future<List<String>> gorulenler() => _liste('gorulenler');
  static Future<void> takipAyarla(List<String> l) => _k.invokeMethod('takipAyarla', {'liste': l});

  static Future<void> tabloHazirla() async {
    await (await DB.db).execute(
        'CREATE TABLE IF NOT EXISTS wa_mesaj(anahtar TEXT PRIMARY KEY, sohbet TEXT, kisi TEXT, metin TEXT, zaman INTEGER)');
  }

  /// Dinleyicinin biriktirdiği mesajları uygulamanın veritabanına alır. Yeni mesaj sayısını döndürür.
  static Future<int> cek() async {
    String? s;
    try {
      s = await _k.invokeMethod<String>('oku');
    } catch (_) {
      return 0;
    }
    if (s == null || s.trim().isEmpty) return 0;
    final satirlar = s.split('\n').where((x) => x.trim().isNotEmpty).toList();
    await tabloHazirla();
    final d = await DB.db;
    var n = 0;
    await d.transaction((tx) async {
      for (final l in satirlar) {
        try {
          final j = jsonDecode(l) as Map<String, dynamic>;
          final metin = '${j['metin']}'.replaceAll(r'\n', '\n');
          final r = await tx.insert(
              'wa_mesaj',
              {
                'anahtar': '${j['sohbet']}|${j['kisi']}|${j['zaman']}|$metin',
                'sohbet': j['sohbet'], 'kisi': j['kisi'], 'metin': metin, 'zaman': j['zaman'],
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          if (r > 0) n++;
        } catch (_) {}
      }
    });
    try {
      await _k.invokeMethod('temizle', {'adet': satirlar.length});
    } catch (_) {}
    return n;
  }

  static Future<List<WaMesaj>> mesajlar({int gun = 90}) async {
    await tabloHazirla();
    final sinir = DateTime.now().subtract(Duration(days: gun)).millisecondsSinceEpoch;
    final r = await DB.q('SELECT * FROM wa_mesaj WHERE zaman>=? ORDER BY zaman', [sinir]);
    return r.map((x) {
      final z = DateTime.fromMillisecondsSinceEpoch((x['zaman'] as int?) ?? 0);
      final kisi = '${x['kisi'] ?? ''}'.trim();
      final m = WaMesaj(tarihS(z), '${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')}',
          kisi.isEmpty ? '${x['sohbet']}' : kisi, '${x['metin']}');
      m.sohbet = '${x['sohbet']}';
      m.tutar = tutarBul(m.metin);
      return m;
    }).toList();
  }

  static Future<int> bekleyenSayisi() async {
    await cek();
    final m = await mesajlar(gun: 30);
    final d = await DB.db;
    var n = 0;
    for (final x in m.where((x) => x.tutar != null)) {
      final r = await d.query('aktarim_hash', where: 'h=?', whereArgs: [x.anahtar]);
      if (r.isEmpty) n++;
    }
    return n;
  }
}

class WaOtomatik extends StatefulWidget {
  const WaOtomatik({super.key});
  @override
  State<WaOtomatik> createState() => _WaOtomatikState();
}

class _WaOtomatikState extends State<WaOtomatik> with WidgetsBindingObserver {
  bool izin = false, yukleniyor = true;
  List<String> takip = [];
  int toplam = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    yukle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) yukle(); // izin ekranından dönünce
  }

  Future<void> yukle() async {
    izin = await WaKanal.izinVarMi();
    takip = await WaKanal.takip();
    await WaKanal.cek();
    toplam = (await WaKanal.mesajlar()).length;
    if (mounted) setState(() => yukleniyor = false);
  }

  Future<void> sohbetEkle() async {
    final gorulen = (await WaKanal.gorulenler()).where((g) => !takip.contains(g)).toList();
    if (!mounted) return;
    final ad = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (_, sc) => ListView(controller: sc, children: [
          const ListTile(
              title: Text('Takip edilecek sohbet', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Listede, izin verildikten sonra bildirimi gelen sohbetler görünür.')),
          ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Adını elle yaz'),
              subtitle: const Text('WhatsApp\'ta göründüğü gibi (kişi veya grup adı)'),
              onTap: () async {
                final x = await metinSor(c, 'Sohbet / grup adı');
                if (x != null && x.isNotEmpty && c.mounted) Navigator.pop(c, x);
              }),
          ...gorulen.map((g) => ListTile(leading: const Icon(Icons.chat), title: Text(g), onTap: () => Navigator.pop(c, g))),
        ]),
      ),
    );
    if (ad == null) return;
    takip = {...takip, ad.trim()}.toList()..sort();
    await WaKanal.takipAyarla(takip);
    setState(() {});
  }

  Future<void> esitle() async {
    final yeni = await WaKanal.cek();
    final m = await WaKanal.mesajlar();
    if (!mounted) return;
    if (m.isEmpty) return mesaj(context, 'Henüz yakalanmış mesaj yok');
    mesaj(context, '$yeni yeni mesaj alındı');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WhatsappAktar(hazir: m, baslik: 'Gelen WhatsApp Mesajları')));
    yukle();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('WhatsApp Otomatik')),
        body: yukleniyor
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(12), children: [
                Card(
                  color: izin ? Colors.green[50] : Colors.orange[50],
                  child: ListTile(
                    leading: Icon(izin ? Icons.check_circle : Icons.notifications_off, color: izin ? Colors.green : Colors.orange),
                    title: Text(izin ? 'Bildirim izni verildi' : 'Bildirim izni gerekli'),
                    subtitle: Text(izin
                        ? 'Seçili sohbetlerden gelen mesajlar uygulama kapalıyken de kaydediliyor.'
                        : 'Açılan listede "Ön Muhasebe"yi bulup izin verin, sonra geri dönün.'),
                    trailing: izin ? null : FilledButton(onPressed: WaKanal.izinAc, child: const Text('İzin ver')),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('Takip edilen sohbetler', style: TextStyle(fontWeight: FontWeight.bold))),
                  TextButton.icon(onPressed: sohbetEkle, icon: const Icon(Icons.add), label: const Text('Ekle')),
                ]),
                if (takip.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Henüz sohbet seçilmedi. Hiçbir mesaj kaydedilmez; sadece seçtiğiniz sohbetler takip edilir.', style: TextStyle(fontSize: 12))),
                Wrap(
                  spacing: 6,
                  children: takip
                      .map((t) => InputChip(
                            label: Text(t),
                            onDeleted: () async {
                              takip.remove(t);
                              await WaKanal.takipAyarla(takip);
                              setState(() {});
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: esitle,
                  icon: const Icon(Icons.sync),
                  label: Padding(padding: const EdgeInsets.all(12), child: Text('Eşitle ($toplam mesaj)', style: const TextStyle(fontSize: 16))),
                ),
                const SizedBox(height: 12),
                const Text(
                    'Eşitle\'ye bastığınızda son 90 günde yakalanan mesajlar listelenir. Tutarlı mesajları seçip tahsilat, ödeme veya gider olarak işlersiniz; işlenenler bir daha gelmez ve diğer telefonlara da eşitlenir.\n\n'
                    'Not: Sadece size gelen ve bildirimi düşen mesajlar yakalanır. Sessize alınmış sohbetleri takip etmek için o sohbetin bildirimlerini açık tutun. Geçmiş mesajlar için "Sohbetten Veri Al" (dışa aktarma) kullanın.',
                    style: TextStyle(fontSize: 12)),
              ]),
      );
}
