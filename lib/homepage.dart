import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:i_zerak_app/pages/gas_station_page.dart';
import 'package:i_zerak_app/subscriptions.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                SizedBox(
                  height: constraints.maxHeight * 0.1,
                  child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Image(
                                image: AssetImage('assets/images/iZerak_logo.png'),
                                width: 50,
                                height: 50),
                            SizedBox(width: 12.0),
                            Text(
                              'iZerak',
                              style: TextStyle(fontSize: 24),
                            ),
                          ])),
                ),
                Expanded(flex: 1, child: _getActivePage(_selectedIndex)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: Container(
        color: Theme.of(context).colorScheme.scrim,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: GNav(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              gap: 8,
              padding: const EdgeInsets.all(16.0),
              onTabChange: (index) => setState(() => _selectedIndex = index),
              selectedIndex: _selectedIndex,
              tabs: [
                GButton(
                  icon: Icons.euro,
                  text: 'Subscriptions',
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
                GButton(
                  icon: Icons.local_gas_station,
                  text: 'Gas stations',
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
              ]),
        ),
      ),
    );
  }
}

Widget _getActivePage(int index) {
  switch (index) {
    case 0:
      return const SubscriptionsPage();
    case 1:
      return GasStationPage();
    default:
      throw Exception('Invalid index');
  }
}
