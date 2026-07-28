import 'dart:async';
import 'dart:ui' show FontLoader;

import 'package:flutter/services.dart' show rootBundle;

/// flutter_test picks this file up automatically for every test under
/// test/ (no import needed anywhere). Without it, the flutter_tester
/// environment has no real fonts loaded at all — every glyph renders as a
/// blank box, which is unreadable for an app whose UI is almost entirely
/// Thai text. Loads the same font the app itself uses (see pubspec.yaml's
/// fonts: and lib/main.dart's ThemeData(fontFamily: 'Loma')) so golden
/// images actually show the text they're supposed to.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _loadThaiFont();
  await testMain();
}

Future<void> _loadThaiFont() async {
  final fontLoader = FontLoader('Loma')
    ..addFont(rootBundle.load('assets/fonts/Loma.otf'))
    ..addFont(rootBundle.load('assets/fonts/Loma-Bold.otf'));
  await fontLoader.load();
}
