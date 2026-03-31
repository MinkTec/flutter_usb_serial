import 'package:flutter/material.dart';

import 'screens/devices_screen.dart';
import 'services/command_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CommandStore.instance.load();
  runApp(const UsbSerialApp());
}

class UsbSerialApp extends StatelessWidget {
  const UsbSerialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USB Serial',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BCD4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
      home: const DevicesScreen(),
    );
  }
}
