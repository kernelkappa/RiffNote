// Basic smoke test: the app boots and shows the home screen with the
// record button, with no recordings yet (fresh test environment).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:riffnote/main.dart';

/// Points the app's documents directory at a throwaway temp folder so the
/// test never touches real platform channels or real user data.
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = await Directory.systemTemp.createTemp('riffnote_test_');
    return dir.path;
  }
}

void main() {
  setUp(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  testWidgets('App boots and shows the empty recordings state', (
    WidgetTester tester,
  ) async {
    // initState kicks off real file I/O (listing the documents directory),
    // which the fake-time test zone can't resolve on its own, and the
    // loading spinner animates indefinitely so pumpAndSettle would never
    // return: drive everything explicitly inside a real event loop instead.
    await tester.runAsync(() async {
      await tester.pumpWidget(const RiffNoteApp());
      await tester.pump();
      await tester.pump();
    });

    expect(find.text('RiffNote'), findsOneWidget);
    expect(find.text('Registra'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}
