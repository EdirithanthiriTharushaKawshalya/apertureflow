import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'repositories/booking_repository.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();

  runApp(ApertureFlowApp(repository: LocalBookingRepository()));
}

/// The root widget of the ApertureFlow Availability and Rental Management application.
/// Configures a premium light-themed UI tailored for professional photographers.
class ApertureFlowApp extends StatelessWidget {
  final BookingRepository repository;

  const ApertureFlowApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApertureFlow',
      debugShowCheckedModeBanner: false,
      // Premium Dashboard layout light theme configuration (Neumorphic styling)
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFEBF1F5), // Light blue-grey background
        primaryColor: const Color(0xFF0F172A), // Slate Dark Accent
        fontFamily: GoogleFonts.quicksand().fontFamily,
        textTheme: GoogleFonts.quicksandTextTheme(ThemeData.light().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          brightness: Brightness.light,
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF0F172A),
          surface: Colors.white,
          background: const Color(0xFFEBF1F5),
          error: Colors.redAccent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
          titleTextStyle: GoogleFonts.quicksand(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      home: HomeScreen(repository: repository),
    );
  }
}
