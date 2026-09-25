import 'package:flutter/material.dart';
import '../services/wear_service.dart';
import 'phone_files_screens.dart';
import 'watch_files_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _watchConnected = false;
  String _watchName = '';
  bool _checkingConnection = true;

  @override
  void initState() {
    super.initState();
    WearService.init();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() => _checkingConnection = true);
    try {
      final nodes = await WearService.getConnectedNodes();
      setState(() {
        _watchConnected = nodes.isNotEmpty;
        _watchName = nodes.isNotEmpty ? nodes.first.displayName : '';
        _checkingConnection = false;
      });
    } catch (_) {
      setState(() {
        _watchConnected = false;
        _checkingConnection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      WatchFilesScreen(watchConnected: _watchConnected),
      const PhoneFilesScreen(),
      const StatsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('TT Analyst'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _checkingConnection
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : GestureDetector(
                    onTap: _checkConnection,
                    child: Row(
                      children: [
                        Icon(
                          _watchConnected
                              ? Icons.watch_rounded
                              : Icons.watch_off_rounded,
                          size: 18,
                          color: _watchConnected
                              ? Colors.greenAccent
                              : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _watchConnected ? _watchName : 'Not connected',
                          style: TextStyle(
                            fontSize: 12,
                            color: _watchConnected
                                ? Colors.greenAccent
                                : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.refresh, size: 14, color: Colors.grey),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.watch_outlined),
            selectedIcon: Icon(Icons.watch),
            label: 'Watch files',
          ),
          NavigationDestination(
            icon: Icon(Icons.phone_android_outlined),
            selectedIcon: Icon(Icons.phone_android),
            label: 'Phone files',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}
