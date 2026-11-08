import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'aktar.dart';
import 'db.dart';
import 'ortak.dart';

/// e-Devlet, GİB, SGK, Enerya, Gasline-Prizma, DİPOS IV vb. portallar.
/// Oturumu kullanıcı kendisi açar; şifre uygulamada saklanmaz (oturum çerezi WebView'da kalır).
class PortalListe extends StatefulWidget {
  const PortalListe({super.key});
  @override
  State<PortalListe> createState() => _PortalListeState();
}

class _PortalListeState extends State<PortalListe> {
  List<Map<String, Object?>> l = [];
  @override
  void initState() {
    super.initState();
    yukle();
  }

  Future<void> yukle() async {
    l = await DB.q('SELECT * FROM portal ORDER BY kategori, id');
    if (mounted) setState(() {});
  }

  Future<void> duzenle([Map<String, Object?>? p]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PortalForm(p)));
    yukle();
  }

  @override
  Widget build(BuildContext context) {
    final gruplar = <String, List<Map<String, Object?>>>{};
    for (final p in l) {
      gruplar.putIfAbsent('${p['kategori'] ?? 'Diğer'}', () => []).add(p);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Portallar ve Entegrasyonlar')),
      floatingActionButton: FloatingActionButton(onPressed: () => duzenle(), child: const Icon(Icons.add)),
      body: ListView(children: [
        const Card(
          margin: EdgeInsets.all(8),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
                '1) Portala dokunun, girişi kendiniz yapın (e-Devlet şifresi, SMS vb.).\n'
                '2) Verinin olduğu sayfaya gidin (borç listesi, fatura listesi, proje listesi...).\n'
                '3) ▦ "Tabloları al" ile sayfadaki tabloyu seçip muhasebeye aktarın; eşlemeyi kaydederseniz sonraki seferlerde ⚡ tek dokunuşla aktarılır.\n'
                'Şifreleriniz uygulamaya kaydedilmez. Uzun basarak adres düzenlenir.',
                style: TextStyle(fontSize: 12.5)),
          ),
        ),
        for (final g in gruplar.entries) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(g.key, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
          ...g.value.map((p) {
            final url = '${p['url'] ?? ''}';
            return ListTile(
              leading: const Icon(Icons.language),
              title: Text('${p['ad']}'),
              subtitle: Text(url.isEmpty ? 'Adres girilmedi — uzun basıp ekleyin' : url, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: p['otomatik'] != null ? const Icon(Icons.bolt, color: Colors.amber) : null,
              onTap: () async {
                if (url.isEmpty) return duzenle(p);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => PortalWeb(p)));
                yukle();
              },
              onLongPress: () => duzenle(p),
            );
          }),
        ],
        const SizedBox(height: 80),
      ]),
    );
  }
}

class PortalForm extends StatefulWidget {
  final Map<String, Object?>? p;
  const PortalForm(this.p, {super.key});
  @override
  State<PortalForm> createState() => _PortalFormState();
}

class _PortalFormState extends State<PortalForm> {
  late final ad = TextEditingController(text: '${widget.p?['ad'] ?? ''}');
  late final url = TextEditingController(text: '${widget.p?['url'] ?? 'https://'}');
  late final kat = TextEditingController(text: '${widget.p?['kategori'] ?? ''}');
  late final not = TextEditingController(text: '${widget.p?['notlar'] ?? ''}');

  Future<void> kaydet() async {
    var u = url.text.trim();
    if (u.isNotEmpty && u != 'https://' && !u.startsWith('http')) u = 'https://$u';
    if (u == 'https://') u = '';
    final m = {'ad': ad.text.trim(), 'url': u, 'kategori': kat.text.trim().isEmpty ? 'Diğer' : kat.text.trim(), 'notlar': not.text.trim()};
    if (widget.p == null) {
      await DB.ekle('portal', m);
    } else {
      await DB.guncelle('portal', m, widget.p!['id'] as int);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.p == null ? 'Yeni Portal' : 'Portal Düzenle'), actions: [
          if (widget.p != null)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await onay(context, 'Portal listeden silinsin mi?')) {
                    await DB.sil('portal', widget.p!['id'] as int);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
          IconButton(icon: const Icon(Icons.check), onPressed: kaydet),
        ]),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Girdi(ad, 'Ad'),
          Girdi(url, 'Giriş adresi (URL)'),
          Girdi(kat, 'Kategori'),
          Girdi(not, 'Not (hangi sayfadan ne alınacak vb.)', satir: 3),
          if (widget.p?['otomatik'] != null)
            OutlinedButton.icon(
                icon: const Icon(Icons.bolt),
                label: const Text('Kayıtlı otomatik aktarım eşlemesini sil'),
                onPressed: () async {
                  final d = await DB.db;
                  await DB.upd(d, 'portal', {'otomatik': null}, where: 'id=?', whereArgs: [widget.p!['id']]);
                  if (context.mounted) mesaj(context, 'Eşleme silindi');
                }),
        ]),
      );
}

/// Sayfadaki tüm tabloları (iframe'ler ve div tabanlı gridler dahil) JSON olarak döndüren betik
const _tabloJs = r'''
(function(){
  function txt(e){return ((e.innerText||e.textContent||'')+'').replace(/\s+/g,' ').trim();}
  var out=[];
  function scan(doc){
    if(!doc) return;
    var ts=doc.querySelectorAll('table');
    for(var i=0;i<ts.length;i++){
      if(ts[i].querySelector('table')) continue;
      var rows=[];var trs=ts[i].querySelectorAll('tr');
      for(var j=0;j<trs.length;j++){
        var cs=trs[j].querySelectorAll('th,td');var r=[];
        for(var k=0;k<cs.length;k++){r.push(txt(cs[k]));}
        if(r.join('').length>0) rows.push(r);
      }
      if(rows.length>1) out.push(rows);
    }
    var rr=doc.querySelectorAll('[role=row]');
    if(rr.length>1){
      var rows2=[];
      for(var j=0;j<rr.length;j++){
        var cs=rr[j].querySelectorAll('[role=cell],[role=gridcell],[role=columnheader]');var r=[];
        for(var k=0;k<cs.length;k++){r.push(txt(cs[k]));}
        if(r.length) rows2.push(r);
      }
      if(rows2.length>1) out.push(rows2);
    }
    var fr=doc.querySelectorAll('iframe,frame');
    for(var f=0;f<fr.length;f++){try{scan(fr[f].contentDocument);}catch(e){}}
  }
  scan(document);
  return JSON.stringify(out);
})();
''';

class PortalWeb extends StatefulWidget {
  final Map<String, Object?> portal;
  const PortalWeb(this.portal, {super.key});
  @override
  State<PortalWeb> createState() => _PortalWebState();
}

class _Bulgu {
  final List<List<String>> satirlar;
  final Hedef? hedef;
  final int veri;
  _Bulgu(this.satirlar, this.hedef, this.veri);
}

class _PortalWebState extends State<PortalWeb> {
  late final WebViewController c;
  double ilerleme = 0;
  Map<String, dynamic>? oto;
  Timer? _tarayici;
  bool _taraniyor = false;
  final _gorulen = <String>{};
  List<_Bulgu> bulgular = [];

  @override
  void dispose() {
    _tarayici?.cancel();
    super.dispose();
  }

  /// Sayfadaki tabloları düzenli aralıklarla tarar, uygulamadaki bölümlerle eşleşenleri sorar.
  Future<void> tara() async {
    if (_taraniyor || !mounted) return;
    _taraniyor = true;
    try {
      final t = await tablolar();
      final url = await c.currentUrl() ?? '';
      final yeni = <_Bulgu>[];
      for (final rows in t) {
        final b = baslikSatiriBul(rows);
        final veri = rows.skip(b + 1).where((r) => r.any((x) => x.trim().isNotEmpty)).length;
        if (veri < 1) continue;
        final imza = '$url|${rows[b].join('|')}|${rows.length}|${rows.last.join('|')}';
        if (_gorulen.contains(imza)) continue;
        final h = enIyiHedef(rows);
        if (h == null && veri < 3) continue;
        _gorulen.add(imza);
        yeni.add(_Bulgu(rows, h, veri));
      }
      if (yeni.isNotEmpty && mounted) setState(() => bulgular = [...bulgular, ...yeni]);
    } catch (_) {
    } finally {
      _taraniyor = false;
    }
  }

  bool _otoUyar(_Bulgu b) {
    if (oto == null) return false;
    final istenen = Map<String, String>.from(oto!['esle'] as Map).values.map(normal).toSet();
    if (istenen.isEmpty) return false;
    final bas = b.satirlar[baslikSatiriBul(b.satirlar)].map(normal).toSet();
    return istenen.where(bas.contains).length >= (istenen.length / 2).ceil();
  }

  Future<void> bulguAktar(_Bulgu b, {bool hizli = false}) async {
    setState(() => bulgular.remove(b));
    if (hizli) {
      final s = await otomatikAktar([b.satirlar], oto!, '${widget.portal['ad']}');
      if (mounted) showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Aktarım'), content: Text(s)));
      return;
    }
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => EslestirmeEkrani(
                satirlar: b.satirlar, kaynak: '${widget.portal['ad']}', portalId: widget.portal['id'] as int, varsayilanHedef: b.hedef?.kod ?? 'serbest')));
    if (ok == true) {
      final p = await DB.tek('SELECT otomatik FROM portal WHERE id=?', [widget.portal['id']]);
      final o = p?['otomatik'] as String?;
      if (mounted) setState(() => oto = o == null ? null : jsonDecode(o) as Map<String, dynamic>);
    }
  }

  Widget? bulguPaneli() {
    if (bulgular.isEmpty) return null;
    final b = bulgular.first;
    final bas = b.satirlar[baslikSatiriBul(b.satirlar)].where((x) => x.trim().isNotEmpty).take(5).join(' • ');
    final hizli = _otoUyar(b);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    b.hedef != null ? '${b.veri} satır "${b.hedef!.ad}" verisi bulundu' : '${b.veri} satırlık tablo bulundu',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (bulgular.length > 1) Text('1/${bulgular.length}', style: const TextStyle(fontSize: 12)),
            ]),
            Text(bas, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(b.hedef != null ? 'Uygulamaya aktarılsın mı?' : 'Olduğu gibi saklansın mı ya da bir bölüme aktarılsın mı?', style: const TextStyle(fontSize: 13)),
            Wrap(spacing: 8, children: [
              if (hizli)
                FilledButton.icon(onPressed: () => bulguAktar(b, hizli: true), icon: const Icon(Icons.bolt), label: const Text('Hızlı aktar')),
              if (hizli)
                OutlinedButton(onPressed: () => bulguAktar(b), child: const Text('Kontrol edip aktar'))
              else
                FilledButton(onPressed: () => bulguAktar(b), child: const Text('Kontrol edip aktar')),
              TextButton(onPressed: () => setState(() => bulgular.remove(b)), child: const Text('Yoksay')),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final o = widget.portal['otomatik'] as String?;
    if (o != null) oto = jsonDecode(o) as Map<String, dynamic>;
    c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => ilerleme = p / 100);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => bulgular = []);
        },
        onPageFinished: (_) => Future.delayed(const Duration(milliseconds: 1500), tara),
      ))
      ..loadRequest(Uri.parse('${widget.portal['url']}'));
    // Sayfa yenilenmeden içerik değişen siteler (sorgu sonuçları) için düzenli tarama
    _tarayici = Timer.periodic(const Duration(seconds: 4), (_) => tara());
  }

  Future<List<List<List<String>>>> tablolar() async {
    final r = await c.runJavaScriptReturningResult(_tabloJs);
    dynamic v = r is String ? r : r.toString();
    v = jsonDecode(v as String);
    if (v is String) v = jsonDecode(v);
    return (v as List).map((t) => (t as List).map((row) => (row as List).map((x) => '$x').toList()).toList()).toList();
  }

  Future<void> tabloSec() async {
    List<List<List<String>>> t;
    try {
      t = await tablolar();
    } catch (e) {
      if (mounted) mesaj(context, 'Sayfa okunamadı: $e');
      return;
    }
    if (!mounted) return;
    if (t.isEmpty) {
      return mesaj(context, 'Bu sayfada tablo bulunamadı. Listeyi/sorgu sonucunu ekrana getirip tekrar deneyin.');
    }
    final i = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (_, sc) => ListView(controller: sc, children: [
          ListTile(title: Text('${t.length} tablo bulundu', style: const TextStyle(fontWeight: FontWeight.bold))),
          ...List.generate(
              t.length,
              (i) => ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text('${t[i].length} satır • ${t[i].first.take(4).join(' | ')}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: t[i].length > 1 ? Text(t[i][1].take(4).join(' | '), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                    onTap: () => Navigator.pop(context, i),
                  )),
        ]),
      ),
    );
    if (i == null || !mounted) return;
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => EslestirmeEkrani(satirlar: t[i], kaynak: '${widget.portal['ad']}', portalId: widget.portal['id'] as int, varsayilanHedef: _varsayilan())));
    if (ok == true) {
      final p = await DB.tek('SELECT otomatik FROM portal WHERE id=?', [widget.portal['id']]);
      final o = p?['otomatik'] as String?;
      setState(() => oto = o == null ? null : jsonDecode(o) as Map<String, dynamic>);
    }
  }

  String _varsayilan() {
    final a = normal('${widget.portal['ad']} ${widget.portal['kategori']}');
    if (a.contains('earsiv') || a.contains('fatura')) return 'satis_fatura';
    if (a.contains('sgk') || a.contains('bagkur') || a.contains('vergi') || a.contains('gib') || a.contains('ceza') || a.contains('trafik')) return 'borc_kaydi';
    if (a.contains('dogalgaz') || a.contains('dipos') || a.contains('enerya') || a.contains('gasline')) return 'serbest';
    return 'cari_hareket';
  }

  Future<void> otomatik() async {
    if (oto == null) return;
    try {
      final t = await tablolar();
      final s = await otomatikAktar(t, oto!, '${widget.portal['ad']}');
      if (mounted) showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Otomatik aktarım'), content: Text(s)));
    } catch (e) {
      if (mounted) mesaj(context, 'Aktarılamadı: $e');
    }
  }

  Future<void> metniNotAl() async {
    final r = await c.runJavaScriptReturningResult('document.body ? document.body.innerText : ""');
    var s = r is String ? r : r.toString();
    if (s.startsWith('"')) s = jsonDecode(s) as String;
    s = s.trim();
    if (s.isEmpty || !mounted) return;
    await DB.ekle('notlar', {'tarih': bugun(), 'kaynak': '${widget.portal['ad']}', 'kisi': await c.currentUrl(), 'metin': s.length > 5000 ? s.substring(0, 5000) : s});
    if (mounted) mesaj(context, 'Sayfa metni Notlar\'a kaydedildi');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('${widget.portal['ad']}', style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                tooltip: 'Sayfada geri',
                onPressed: () async {
                  if (await c.canGoBack()) c.goBack();
                }),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => c.reload()),
            if (oto != null) IconButton(icon: const Icon(Icons.bolt, color: Colors.amber), tooltip: 'Kayıtlı eşlemeyle aktar', onPressed: otomatik),
            IconButton(icon: const Icon(Icons.table_view), tooltip: 'Tabloları al', onPressed: tabloSec),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'not') metniNotAl();
                if (v == 'ana') c.loadRequest(Uri.parse('${widget.portal['url']}'));
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'not', child: Text('Sayfa metnini nota kaydet')),
                PopupMenuItem(value: 'ana', child: Text('Giriş sayfasına dön')),
              ],
            ),
          ],
          bottom: ilerleme < 1 ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: ilerleme)) : null,
        ),
        body: Column(children: [
          Expanded(child: WebViewWidget(controller: c)),
          ...[bulguPaneli()].whereType<Widget>(),
        ]),
      );
}
