import 'package:flutter/gestures.dart';
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
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Synchronous — jangan panggil plugin apapun di sini
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
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
    final loggedIn = await AuthService.isLoggedIn();
    if (mounted) setState(() => _loggedIn = loggedIn);
  }

  void _onLoginSuccess() => setState(() => _loggedIn = true);
  void _onLogout() => setState(() => _loggedIn = false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unitas',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _UnitasScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: brandNavy,
          secondary: brandGold,
          surface: brandBg,
        ),
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
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
    return Scaffold(
      backgroundColor: brandBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: brandNavy,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Text(
                'U',
                style: GoogleFonts.outfit(
                  color: brandGold,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Unitas',
              style: GoogleFonts.outfit(
                color: brandNavy,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Menyiapkan ruang alumni…',
              style: TextStyle(color: dim1, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: const LinearProgressIndicator(
                  minHeight: 3,
                  color: brandNavy,
                  backgroundColor: dim3,
                ),
              ),
            ),
          ],
        ),
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
  int _homeRefreshTick = 0;

  late final List<Widget> _otherScreens = [
    const DirectoryScreen(),
    const EventsScreen(),
    const JobsScreen(),
    ProfileScreen(onLogout: widget.onLogout),
  ];

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
        children: [
          HomeScreen(
            refreshTrigger: _homeRefreshTick,
            onOpenDirectory: () => setState(() => _currentIndex = 1),
            onOpenEvents: () => setState(() => _currentIndex = 2),
          ),
          ..._otherScreens,
        ],
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
                  onTap: () => setState(() {
                    if (i == 0 && _currentIndex != 0) {
                      _homeRefreshTick++;
                    }
                    _currentIndex = i;
                  }),
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

class _UnitasScrollBehavior extends MaterialScrollBehavior {
  const _UnitasScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Nonaktifkan StretchingOverscrollIndicator (Material 3) yang sering memicu flicker putih saat scroll di Web
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
