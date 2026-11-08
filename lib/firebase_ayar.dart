import 'package:firebase_core/firebase_core.dart';

/// Firebase Console → Proje ayarları → Uygulamalarınız → Android uygulaması değerleri.
/// Bu değerler gizli değildir; erişimi Firestore kuralları ve kullanıcı girişi korur.
const _apiKey = '';
const _appId = '';
const _senderId = '';
const _projectId = '';

/// Tüm telefonların ortak kullandığı firma alanı (firmalar/<firmaKodu>/...)
const firmaKodu = 'kones';

bool get firebaseAyarli => _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty;

const firebaseSecenekleri = FirebaseOptions(
  apiKey: _apiKey,
  appId: _appId,
  messagingSenderId: _senderId,
  projectId: _projectId,
  storageBucket: '$_projectId.appspot.com',
);
