import 'package:flutter/material.dart';

import '../app/app_state.dart';
import 'home_page.dart';
import 'theme.dart';

class NetturbineApp extends StatelessWidget {
  const NetturbineApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp(
        title: 'netturbine',
        debugShowCheckedModeBanner: false,
        theme: NtTheme.light(),
        darkTheme: NtTheme.dark(),
        themeMode: ThemeMode.system,
        home: HomePage(state: state),
      ),
    );
  }
}
