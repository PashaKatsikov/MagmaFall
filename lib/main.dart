import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MagmaFallApp());
}

class MagmaFallApp extends StatelessWidget {
  const MagmaFallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Magma Fall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: MagmaColors.deepRock,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MagmaColors.ember,
          brightness: Brightness.dark,
        ),
      ),
      home: const LoadingScreen(),
    );
  }
}
