import 'dart:async';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// flutter_test picks this file up automatically for every test under
/// test/ (no import needed anywhere). Without it, the flutter_tester
/// environment has no real fonts loaded at all — every glyph renders as a
/// blank box, which is unreadable for an app whose UI is almost entirely
/// Thai text. Loads the same font the app itself uses (see pubspec.yaml's
/// fonts: and lib/core/theme.dart's buildAppTheme()) so golden images
/// actually show the text they're supposed to.
///
/// A MaterialIcons font load was attempted here too (Icon() widgets like
/// the stall markers' Icons.storefront render as an empty tofu box without
/// it, same root cause as the Thai text problem) but the guessed asset path
/// ("packages/flutter/fonts/MaterialIcons-Regular.otf") doesn't exist in
/// the Flutter SDK version CI resolves -- it hard-crashed every single
/// test ("Unable to load asset"), which is worse than the cosmetic tofu-box
/// issue it was meant to fix. Reverted rather than guess again without a
/// local Flutter SDK to verify the real path against.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // testExecutable runs before any individual test's main(), so nothing has
  // initialized the test binding yet -- rootBundle.load() needs it (it goes
  // through ServicesBinding.instance) or it throws "Binding has not yet
  // been initialized."
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadThaiFont();
  await testMain();
}

Future<void> _loadThaiFont() async {
  final fontLoader = FontLoader('Loma')
    ..addFont(rootBundle.load('assets/fonts/Loma.otf'))
    ..addFont(rootBundle.load('assets/fonts/Loma-Bold.otf'));
  await fontLoader.load();
}
