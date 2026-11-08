import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'db.dart';
import 'guncelleme.dart';
import 'menu.dart';
import 'ortak.dart';
import 'senkron.dart';

/// Firebase ayarlıysa: giriş yapılmamışsa giriş ekranı, yapılmışsa senkronla ana menü
class Kapi extends StatefulWidget {
  const Kapi({super.key});
  @override
  State<Kapi> createState() => _KapiState();
}

class _KapiState extends State<Kapi> {
  bool? cevrimdisi;
  @override
  void initState() {
    super.initState();
    DB.ayarOku('cevrimdisi').then((v) => setState(() => cevrimdisi = v == '1'));
  }

  @override
  Widget build(BuildContext context) {
    if (!Senkron.hazir) return const AnaMenu();
    if (cevrimdisi == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (cevrimdisi!) return const AnaMenu();
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (s.data == null) {
          Senkron.durdur();
          return GirisEkrani(cevrimdisiDevam: () async {
            await DB.ayarYaz('cevrimdisi', '1');
            setState(() => cevrimdisi = true);
          });
        }
        Senkron.baslat();
        return const AnaMenu();
      },
    );
  }
}

class GirisEkrani extends StatefulWidget {
  final VoidCallback cevrimdisiDevam;
  const GirisEkrani({super.key, required this.cevrimdisiDevam});
  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  final eposta = TextEditingController(), sifre = TextEditingController();
  bool bekle = false, gizli = true;

  Future<void> giris() async {
    setState(() => bekle = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: eposta.text.trim(), password: sifre.text);
    } on FirebaseAuthException catch (e) {
      final m = switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'E-posta veya şifre hatalı',
        'invalid-email' => 'E-posta adresi geçersiz',
        'network-request-failed' => 'İnternet bağlantısı yok',
        'too-many-requests' => 'Çok fazla deneme, biraz sonra tekrar deneyin',
        _ => 'Giriş yapılamadı (${e.code})',
      };
      if (mounted) mesaj(context, m);
    } finally {
      if (mounted) setState(() => bekle = false);
    }
  }

  Future<void> sifreSifirla() async {
    if (eposta.text.trim().isEmpty) return mesaj(context, 'Önce e-posta adresinizi yazın');
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: eposta.text.trim());
      if (mounted) mesaj(context, 'Şifre sıfırlama bağlantısı e-postanıza gönderildi');
    } catch (e) {
      if (mounted) mesaj(context, 'Gönderilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 40),
            Icon(Icons.account_balance, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text('Ön Muhasebe', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const Text('Kones Mühendislik', textAlign: TextAlign.center),
            const SizedBox(height: 32),
            TextField(controller: eposta, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 12),
            TextField(
              controller: sifre,
              obscureText: gizli,
              onSubmitted: (_) => giris(),
              decoration: InputDecoration(
                labelText: 'Şifre',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(icon: Icon(gizli ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => gizli = !gizli)),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: bekle ? null : giris, child: Padding(padding: const EdgeInsets.all(12), child: bekle ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Giriş Yap'))),
            TextButton(onPressed: sifreSifirla, child: const Text('Şifremi unuttum')),
            const SizedBox(height: 24),
            const Text('Kullanıcılar yönetici tarafından eklenir. Aynı hesapla giren tüm telefonlar aynı verileri görür.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            TextButton(
                onPressed: () async {
                  if (await onay(context, 'Girişsiz kullanımda veriler sadece bu telefonda kalır, diğer telefonlarla paylaşılmaz. Devam edilsin mi?')) widget.cevrimdisiDevam();
                },
                child: const Text('Girişsiz devam et (sadece bu telefon)')),
          ]),
        ),
      );
}

/// Senkronizasyon durumu, çıkış, güncelleme
class SenkronEkrani extends StatefulWidget {
  const SenkronEkrani({super.key});
  @override
  State<SenkronEkrani> createState() => _SenkronEkraniState();
}

class _SenkronEkraniState extends State<SenkronEkrani> {
  int bekleyen = 0;
  String surum = '';
  @override
  void initState() {
    super.initState();
    yukle();
  }

  Future<void> yukle() async {
    final r = await DB.tek('SELECT COUNT(*) n FROM degisiklik');
    final s = await Guncelleme.surum();
    if (mounted) setState(() {
      bekleyen = (r?['n'] as int?) ?? 0;
      surum = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kullanici = Senkron.hazir ? FirebaseAuth.instance.currentUser : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Eşitleme ve Güncelleme')),
      body: ValueListenableBuilder<String>(
        valueListenable: Senkron.durum,
        builder: (_, d, __) => ListView(children: [
          ListTile(
            leading: Icon(d == 'bagli' ? Icons.cloud_done : d == 'hata' ? Icons.cloud_off : d == 'gonderiyor' ? Icons.cloud_upload : Icons.cloud_queue,
                color: d == 'hata' ? Colors.red : d == 'bagli' ? Colors.green : null),
            title: Text(!Senkron.hazir
                ? 'Bulut eşitleme kurulmamış'
                : kullanici == null
                    ? 'Giriş yapılmadı (veriler sadece bu telefonda)'
                    : d == 'bagli'
                        ? 'Bağlı, veriler eşitleniyor'
                        : d == 'gonderiyor'
                            ? 'Gönderiliyor...'
                            : d == 'hata'
                                ? 'Eşitleme hatası'
                                : 'Kapalı'),
            subtitle: Text([if (kullanici != null) kullanici.email ?? '', 'Gönderilmeyi bekleyen: $bekleyen', if (d == 'hata') Senkron.sonHata].join('\n')),
          ),
          if (kullanici != null) ...[
            ListTile(leading: const Icon(Icons.sync), title: const Text('Şimdi eşitle'), onTap: () async {
              await Senkron.gonder();
              await Senkron.baslat(zorla: true);
              yukle();
            }),
            ListTile(
                leading: const Icon(Icons.cloud_sync),
                title: const Text('Bu telefondaki tüm verileri yeniden gönder'),
                subtitle: const Text('Girişten önce bu telefonda girilmiş kayıtlar buluta gitmediyse'),
                onTap: () async {
                  final n = await Senkron.tumunuIsaretle();
                  if (context.mounted) mesaj(context, '$n kayıt gönderim sırasına alındı');
                  yukle();
                }),
            ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Çıkış yap'),
                onTap: () async {
                  if (!await onay(context, 'Çıkış yapılsın mı? Veriler telefonda kalır.')) return;
                  Senkron.durdur();
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                }),
          ],
          if (Senkron.hazir && kullanici == null)
            ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Giriş yap ve verileri paylaş'),
                onTap: () async {
                  await DB.ayarYaz('cevrimdisi', null);
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Kapi()), (_) => false);
                  }
                }),
          const Divider(),
          ListTile(leading: const Icon(Icons.info_outline), title: Text('Sürüm $surum')),
          ListTile(leading: const Icon(Icons.system_update), title: const Text('Güncellemeleri denetle'), onTap: () => Guncelleme.sor(context, sessiz: false)),
        ]),
      ),
    );
  }
}
