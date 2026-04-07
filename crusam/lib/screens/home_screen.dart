import 'package:flutter/material.dart';
import 'master/employee_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const EmployeeListScreen(),
    Scaffold(
      body: Center(
        child: Text(
          'Vouchers — Coming Soon',
          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
        ),
      ),
    ),
    Scaffold(
      body: Center(
        child: Text(
          'Settings — Coming Soon',
          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {  
    return Row(
      children: [
        NavigationRail(
          extended: false,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.people),
              label: Text('Master Data'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.receipt_long),
              label: Text('Vouchers'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.settings),
              label: Text('Settings'),
            ),
          ],
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Text(
              'CruSam',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
        ),
      ],
    );
  }
}