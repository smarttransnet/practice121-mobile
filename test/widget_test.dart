import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note365_mobile/app/app.dart';
import 'package:note365_mobile/features/transcription/presentation/widgets/voice_orb.dart';

void main() {
  testWidgets('App boots into the transcription screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: Note365App()));
    // Allow async initial frames (Riverpod, go_router) to settle.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Scaffold), findsWidgets);
    expect(find.text('Note365'), findsWidgets);
    expect(find.byType(VoiceOrb), findsOneWidget);
    expect(find.text('Ready when you are'), findsOneWidget);
  });
}
