import 'package:flutter/material.dart';

import '../dictionary/dictionary_screen.dart';
import '../study/study_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  // The dictionary's current category filter — Study follows it, so picking a
  // category in the dictionary (then "study now") studies just that category.
  int? _dictFilterCatId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DictionaryScreen(
            onStudyTap: () => setState(() => _index = 1),
            onFilterChanged: (id) => setState(() => _dictFilterCatId = id),
          ),
          StudyScreen(active: _index == 1, catalogueId: _dictFilterCatId),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Dictionary'),
          NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style),
              label: 'Study'),
        ],
      ),
    );
  }
}
