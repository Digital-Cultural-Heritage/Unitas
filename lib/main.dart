import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/colors.dart';
import 'screens/home_screen.dart';
import 'screens/directory_screen.dart';
import 'screens/events_screen.dart';
import 'screens/jobs_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const UnitasApp());
}

class UnitasApp extends StatelessWidget {
  const UnitasApp({super.key});

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
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    DirectoryScreen(),
    EventsScreen(),
    JobsScreen(),
    ProfileScreen(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.home_outlined,       activeIcon: Icons.home,             label: 'Beranda'),
    _NavItem(icon: Icons.people_outline,      activeIcon: Icons.people,           label: 'Alumni'),
    _NavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'Acara'),
    _NavItem(icon: Icons.work_outline,        activeIcon: Icons.work,             label: 'Karier'),
    _NavItem(icon: Icons.person_outline,      activeIcon: Icons.person,           label: 'Profil'),
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
          border: Border(top: BorderSide(color: Color(0x14_FFFFFF), width: 1)),
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
