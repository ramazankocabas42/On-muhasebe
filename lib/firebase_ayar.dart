import 'package:firebase_core/firebase_core.dart';

/// Firebase Console → Proje ayarları → Uygulamalarınız → Android uygulaması değerleri.
/// Bu değerler gizli değildir; erişimi Firestore kuralları ve kullanıcı girişi korur.
const _apiKey = 'AIzaSyDnaLDbCBoqrhbrk7zmkUhqHUhfsrDNm-k';
const _appId = '1:207268468862:android:df5c5b864ac76dc68f602f';
const _senderId = '207268468862';
const _projectId = 'kones-muhasebe';

/// Tüm telefonların ortak kullandığı firma alanı (firmalar/<firmaKodu>/...)
const firmaKodu = 'kones';

bool get firebaseAyarli => _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty;

const firebaseSecenekleri = FirebaseOptions(
  apiKey: _apiKey,
  appId: _appId,
  messagingSenderId: _senderId,
  projectId: _projectId,
  storageBucket: 'kones-muhasebe.firebasestorage.app',
);
