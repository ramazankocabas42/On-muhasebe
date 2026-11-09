import 'package:flutter/material.dart';

import 'db.dart';
import 'ortak.dart';
import 'servis.dart';

/// Barkodla / aramayla hızlı satış ekranı (perakende kasa)
class HizliSatis extends StatefulWidget {
  final bool iade;
  const HizliSatis({super.key, this.iade = false});
  @override
  State<HizliSatis> createState() => _HizliSatisState();
}

class _HizliSatisState extends State<HizliSatis> {
  final ara = TextEditingController();
  final odak = FocusNode();
  List<Map<String, Object?>> sonuc = [];
  final sepet = <Map<String, Object?>>[];
  int _aramaNo = 0;
  bool _kaydediliyor = false;

  @override
  void dispose() {
    ara.dispose();
    odak.dispose();
    super.dispose();
  }

  /// Yazarken sadece listeler; sepete eklemez. (Önceden yazılan her harfte barkod/kod tam eşleşmesi
  /// aranıyordu: kodu "AB" olan ürün, "AB123" yazılırken sepete giriyor, okuyucu Enter'ı da
  /// gönderince aynı ürün iki kez ekleniyordu.)
  Future<void> listele(String v) async {
    final n = v.trim();
    final no = ++_aramaNo;
    if (n.length < 2) {
      if (sonuc.isNotEmpty) setState(() => sonuc = []);
      return;
    }
    final r = await DB.q('SELECT * FROM urun WHERE ad LIKE ? OR kod LIKE ? OR barkod LIKE ? ORDER BY ad LIMIT 30', ['%$n%', '%$n%', '%$n%']);
    if (!mounted || no != _aramaNo) return; // daha yeni bir arama başladıysa eski sonucu gösterme
    setState(() => sonuc = r);
  }

  /// Enter / barkod okuyucu: tam eşleşen ürünü sepete ekler, yoksa listeler.
  Future<void> bul(String v) async {
    final n = v.trim();
    final no = ++_aramaNo;
    if (n.isEmpty) return setState(() => sonuc = []);
    final tam = await DB.tek('SELECT * FROM urun WHERE barkod=? OR kod=? LIMIT 1', [n, n]);
    if (!mounted) return;
    if (tam != null) {
      ekle(tam);
      ara.clear();
      setState(() => sonuc = []);
      odak.requestFocus(); // sıradaki barkod için alan hazır kalsın
      return;
    }
    final r = await DB.q('SELECT * FROM urun WHERE ad LIKE ? OR kod LIKE ? OR barkod LIKE ? ORDER BY ad LIMIT 30', ['%$n%', '%$n%', '%$n%']);
    if (!mounted || no != _aramaNo) return;
    setState(() => sonuc = r);
    if (r.isEmpty) mesaj(context, 'Ürün bulunamadı: $n');
    odak.requestFocus();
  }

  void ekle(Map<String, Object?> u) {
    final i = sepet.indexWhere((s) => s['urun_id'] == u['id']);
    setState(() {
      if (i >= 0) {
        sepet[i]['miktar'] = sy(sepet[i]['miktar']) + 1;
      } else {
        sepet.add({'urun_id': u['id'], 'urun_ad': u['ad'], 'birim': u['birim'], 'miktar': 1.0, 'fiyat': sy(u['satis_fiyat']), 'kdv': sy(u['kdv']), 'iskonto': 0.0});
      }
    });
  }

  double get toplam => sepet.fold<double>(0.0, (a, s) => a + sy(s['miktar']) * sy(s['fiyat']) * (1 + sy(s['kdv']) / 100));

  Future<void> bitir(String sekil) async {
    // Düğmeye hızlı iki kez basılınca satış iki kez kaydediliyordu
    if (sepet.isEmpty || _kaydediliyor) return;
    _kaydediliyor = true;
    try {
      Map<String, Object?>? cari;
      int? hesap;
      if (sekil == 'veresiye') {
        cari = await cariSec(context);
        if (cari == null) return;
      } else {
        hesap = await Servis.ilkHesap(sekil == 'nakit' ? 'kasa' : 'banka');
      }
      final tur = widget.iade ? 'hizli_satis_iade' : 'hizli_satis';
      final tutar = toplam;
      await Servis.belgeKaydet({
        'tur': tur, 'no': await Servis.sonrakiNo(tur), 'tarih': bugun(), 'depo_id': 1, 'cari_id': cari?['id'],
        'odeme': sekil == 'veresiye' ? 'acik' : 'pesin', 'hesap_id': hesap, 'aciklama': sekil == 'kart' ? 'Kredi kartı' : sekil == 'nakit' ? 'Nakit' : 'Veresiye',
      }, sepet);
      if (!mounted) return;
      mesaj(context, '${widget.iade ? 'İade' : 'Satış'} tamamlandı: ${para(tutar)}');
      setState(() => sepet.clear());
      odak.requestFocus();
    } finally {
      _kaydediliyor = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.iade ? 'Hızlı Satış İade' : 'Hızlı Satış'), actions: [
          if (sepet.isNotEmpty) IconButton(icon: const Icon(Icons.delete_sweep), onPressed: () => setState(() => sepet.clear())),
        ]),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: ara,
              focusNode: odak,
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.qr_code_scanner), hintText: 'Barkod okut veya ürün adı yaz'),
              onChanged: listele,
              onSubmitted: bul,
            ),
          ),
          if (sonuc.isNotEmpty)
            SizedBox(
              height: 160,
              child: ListView(
                  children: sonuc
                      .map((u) => ListTile(
                          dense: true,
                          title: Text('${u['ad']}'),
                          trailing: Text(para(sy(u['satis_fiyat']) * (1 + sy(u['kdv']) / 100))),
                          onTap: () {
                            ekle(u);
                            ara.clear();
                            setState(() => sonuc = []);
                          }))
                      .toList()),
            ),
          const Divider(),
          Expanded(
            child: ListView(
              children: sepet.asMap().entries.map((e) {
                final s = e.value;
                return ListTile(
                  title: Text('${s['urun_ad']}'),
                  subtitle: Text('${para(sy(s['fiyat']) * (1 + sy(s['kdv']) / 100))} (KDV dahil)'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() {
                              final m = sy(s['miktar']) - 1;
                              if (m <= 0) {
                                sepet.removeAt(e.key);
                              } else {
                                s['miktar'] = m;
                              }
                            })),
                    Text(miktarS(s['miktar']), style: const TextStyle(fontSize: 16)),
                    IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => s['miktar'] = sy(s['miktar']) + 1)),
                  ]),
                );
              }).toList(),
            ),
          ),
          Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.all(12),
            child: SafeArea(
              top: false,
              child: Column(children: [
                Row(children: [
                  const Text('TOPLAM', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(para(toplam), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: () => bitir('nakit'), icon: const Icon(Icons.payments), label: const Text('Nakit'))),
                  const SizedBox(width: 6),
                  Expanded(child: FilledButton.icon(onPressed: () => bitir('kart'), icon: const Icon(Icons.credit_card), label: const Text('Kart'))),
                  const SizedBox(width: 6),
                  Expanded(child: OutlinedButton.icon(onPressed: () => bitir('veresiye'), icon: const Icon(Icons.person), label: const Text('Veresiye'))),
                ]),
              ]),
            ),
          ),
        ]),
      );
}

class FiyatGor extends StatefulWidget {
  const FiyatGor({super.key});
  @override
  State<FiyatGor> createState() => _FiyatGorState();
}

class _FiyatGorState extends State<FiyatGor> {
  Map<String, Object?>? u;
  double stok = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fiyat Gör')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.qr_code_scanner), hintText: 'Barkod / kod / ad'),
              onSubmitted: (v) async {
                final r = await DB.tek('SELECT * FROM urun WHERE barkod=? OR kod=? OR ad LIKE ? LIMIT 1', [v.trim(), v.trim(), '%${v.trim()}%']);
                stok = r == null ? 0 : await Servis.stok(r['id'] as int);
                setState(() => u = r);
              },
            ),
            const SizedBox(height: 40),
            if (u != null) ...[
              Text('${u!['ad']}', style: const TextStyle(fontSize: 22), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(para(sy(u!['satis_fiyat']) * (1 + sy(u!['kdv']) / 100)), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
              Text('KDV dahil • KDV hariç ${para(u!['satis_fiyat'])}'),
              const SizedBox(height: 12),
              Text('Stok: ${miktarS(stok)} ${u!['birim'] ?? ''}'),
            ],
          ]),
        ),
      );
}
