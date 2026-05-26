// Example Flutter source used to verify the automator's behavior on a
// representative set of strings. Run from the package root:
//
//   cd example/sample_app
//   flutter pub get
//   dart run l10n_automator init
//   dart run l10n_automator scan

import 'package:flutter/material.dart';
import 'package:l10n_automator/l10n_automator.dart';

const appTitle = 'My Cool App';

void main() {
  runApp(
    const L10nAutomatorBootstrap(
      reviewReportPath: '.localizator/last_run.json',
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      home: const HomePage(),
      routes: {
        '/details': (_) => const Scaffold(body: Center(child: Text('Detail page'))),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    const username = 'Sam';
    const count = 3;

    // l10n:ignore
    debugPrint('mounted home page');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
      ),
      body: Column(
        children: [
          const Text('Hello, $username'),
          const Text('You have $count messages'),
          const SelectableText('Tap below to continue'),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search...',
              labelText: 'Query',
            ),
          ),
          Image.asset('assets/images/logo.png'),
          ElevatedButton(
            onPressed: () {
              Navigator.pushNamed(context, '/details');
            },
            // l10n:key=continueCta
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
