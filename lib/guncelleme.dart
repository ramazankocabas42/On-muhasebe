import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ortak.dart';

/// GitHub Releases üzerinden uygulama içi güncelleme
class Guncelleme {
  static const depo = 'ramazankocabas42/On-muhasebe';
  static bool _soruldu = false;

  static Future<String> surum() async {
    final i = await PackageInfo.fromPlatform();
    return '${i.version} (${i.buildNumber})';
  }

  static Future<Map<String, String>?> kontrol() async {
    final i = await PackageInfo.fromPlatform();
    final mevcut = int.tryParse(i.buildNumber) ?? 0;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final rq = await c.getUrl(Uri.parse('https://api.github.com/repos/$depo/releases/latest'));
      rq.headers.set('User-Agent', 'on-muhasebe');
      rq.headers.set('Accept', 'application/vnd.github+json');
      final rs = await rq.close().timeout(const Duration(seconds: 15));
      if (rs.statusCode != 200) return null;
      final j = jsonDecode(await rs.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final tag = '${j['tag_name']}';
      final yeni = int.tryParse(tag.split('.').last) ?? 0;
      if (yeni <= mevcut) return null;
      final apk = (j['assets'] as List).cast<Map<String, dynamic>>().where((a) => '${a['name']}'.endsWith('.apk')).toList();
      if (apk.isEmpty) return null;
      return {'surum': tag, 'url': '${apk.first['browser_download_url']}', 'not': '${j['body'] ?? ''}'};
    } catch (_) {
      return null;
    } finally {
      c.close();
    }
  }

  static Future<void> sor(BuildContext context, {bool sessiz = true}) async {
    if (sessiz && _soruldu) return;
    _soruldu = true;
    final g = await kontrol();
    if (!context.mounted) return;
    if (g == null) {
      if (!sessiz) mesaj(context, 'Uygulama güncel');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Yeni sürüm: ${g['surum']}'),
        content: const Text('Güncelle\'ye dokunduğunuzda APK indirilir. İndirme bitince dosyaya dokunup "Güncelle"yi seçin. Verileriniz silinmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Sonra')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Güncelle')),
        ],
      ),
    );
    if (ok == true) await launchUrl(Uri.parse(g['url']!), mode: LaunchMode.externalApplication);
  }
}
