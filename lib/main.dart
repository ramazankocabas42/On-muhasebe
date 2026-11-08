import 'package:flutter/material.dart';

import 'giris.dart';
import 'senkron.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Senkron.firebaseBaslat();
  runApp(const OnMuhasebeApp());
}

class OnMuhasebeApp extends StatelessWidget {
  const OnMuhasebeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ön Muhasebe',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF00897B),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
        ),
        home: const Kapi(),
      );
}
