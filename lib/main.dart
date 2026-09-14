import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/colors.dart';
import 'core/api/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/directory_screen.dart';
import 'screens/events_screen.dart';
import 'screens/jobs_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  // Synchronous — jangan panggil plugin apapun di sini
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const UnitasApp());
}

class UnitasApp extends StatefulWidget {
  const UnitasApp({super.key});

  @override
  State<UnitasApp> createState() => _UnitasAppState();
}

class _UnitasAppState extends State<UnitasApp> {
  // null = masih loading, true = sudah login, false = belum login
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    // Panggil SETELAH widget mounted — plugin sudah terdaftar
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final loggedIn = await AuthService.isLoggedIn();
      if (mounted) setState(() => _loggedIn = loggedIn);
    } catch (_) {
      if (mounted) setState(() => _loggedIn = false);
    }
  }

  void _onLoginSuccess() => setState(() => _loggedIn = true);
  void _onLogout() => setState(() => _loggedIn = false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unitas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: brandNavy,
          secondary: brandGold,
          surface: brandBg,
        ),
        textTheme: GoogleFonts.outfitTextTheme(),
        scaffoldBackgroundColor: brandBg,
        useMaterial3: true,
      ),
      home: switch (_loggedIn) {
        null  => const _SplashScreen(),
        true  => MainShell(onLogout: _onLogout),
        false => LoginScreen(onLoginSuccess: _onLoginSuccess),
      },
    );
  }
}

// ── Splash / Loading screen ────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: brandBg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: brandNavy, strokeWidth: 2),
          SizedBox(height: 20),
          Text('Memuat…', style: TextStyle(color: Color(0x991E3A5F), fontSize: 13)),
        ]),
      ),
    );
  }
}

// ── Main shell with bottom nav ─────────────────────────────────────────────
class MainShell extends StatefulWidget {
  final VoidCallback onLogout;
  const MainShell({super.key, required this.onLogout});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      const DirectoryScreen(),
      const EventsScreen(),
      const JobsScreen(),
      ProfileScreen(onLogout: widget.onLogout),
    ];
  }

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.home_outlined,           activeIcon: Icons.home,           label: 'Beranda'),
    _NavItem(icon: Icons.people_outline,          activeIcon: Icons.people,         label: 'Alumni'),
    _NavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'Acara'),
    _NavItem(icon: Icons.work_outline,            activeIcon: Icons.work,           label: 'Karier'),
    _NavItem(icon: Icons.person_outline,          activeIcon: Icons.person,         label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: Color(0x14FFFFFF), width: 1)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _navItems.asMap().entries.map((e) {
                final i = e.key; final item = e.value;
                final isActive = i == _currentIndex;
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        isActive ? item.activeIcon : item.icon,
                        color: isActive ? navIconActive : navIconInactive,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                          color: isActive ? navIconActive : navIconInactive,
                        ),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
