// lib/main.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Core DB
import 'db/database_helper.dart';

// Screens
import 'screens/dashboard_screen.dart';
import 'screens/add_loan_screen.dart';
import 'screens/loan_details_screen.dart';

// ==============================================================================
// 1. APP ENTRY POINT
// ==============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Pre-warm database (optional but nice)
  try {
    await DatabaseHelper.instance.database;
    debugPrint('✅ Database initialized');
  } catch (e, st) {
    debugPrint('❌ Error initializing database: $e');
    debugPrint(st.toString());
  }

  runApp(const LoanManagerApp());
}

// ==============================================================================
// 2. THEME CONFIGURATION
// ==============================================================================

class AppTheme {
  static const Color primary = Color(0xFF6366F1);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color textDark = Color(0xFF1E293B);
  static const Color error = Color(0xFFEF4444);

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: Colors.white,
        background: backgroundLight,
        error: error,
      ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundLight,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: textDark),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: Color(0xFF1E293B),
        background: backgroundDark,
      ),
      scaffoldBackgroundColor: backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundDark,
        elevation: 0,
      ),
      useMaterial3: true,
    );
  }
}

// ==============================================================================
// 3. ROOT APP
// ==============================================================================

class LoanManagerApp extends StatelessWidget {
  const LoanManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Loan Manager',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const DashboardScreen(),
      routes: {
        '/dashboard': (context) => const DashboardScreen(),
        '/addLoan': (context) => const AddLoanScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/loanDetails') {
          final loanId = settings.arguments as int;
          return MaterialPageRoute(
            builder: (context) => LoanDetailsScreen(loanId: loanId),
          );
        }
        return null;
      },
    );
  }
}
