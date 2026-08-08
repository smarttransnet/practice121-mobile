import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note365_mobile/features/transcription/data/services/favorites_service.dart';
import 'package:note365_mobile/features/transcription/presentation/widgets/clinical_note_panel.dart';
import 'package:note365_mobile/features/transcription/presentation/widgets/prescription_grid_widget.dart';

const _noteWithPrescription = '''
**Chief Complaint**
Fever

**Doctor Prescription**
Paracetamol / Panadol - 500 mg - TDS - 5 days
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Phone-sized viewport + large IME, matching the emulator screenshot.
  const screenSize = Size(400, 800);
  const keyboardHeight = 400.0;

  Rect? globalRect(Finder finder) {
    final elements = finder.evaluate();
    if (elements.isEmpty) return null;
    final box = elements.first.renderObject as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  testWidgets(
    'focused prescription field stays visible above the keyboard',
    (tester) async {
      await tester.binding.setSurfaceSize(screenSize);
      tester.view.physicalSize = screenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() async {
        tester.view.reset();
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoriteMedicinesProvider.overrideWith(
              (ref) async => FavoritesService.defaultFallbackFavorites,
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ClinicalNotePanel.show(
                      context,
                      note: _noteWithPrescription,
                      fullTranscript: 'patient has fever for two days',
                      onNewSession: () {},
                    ),
                    child: const Text('Open note'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open note'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Prescription'));
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Send SMS Prescription'), findsOneWidget);

      final gridBefore = globalRect(find.byType(PrescriptionGridWidget));
      expect(gridBefore, isNotNull);
      expect(gridBefore!.height, greaterThan(120));

      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final keyboardTop = screenSize.height - keyboardHeight;
      final gridAfter = globalRect(find.byType(PrescriptionGridWidget));
      final amendRect = globalRect(find.text('Talk or type to edit...'));

      expect(
        find.text('Close'),
        findsNothing,
        reason: 'Action chrome hides while the keyboard is open',
      );
      expect(find.text('Send SMS Prescription'), findsNothing);

      expect(gridAfter, isNotNull);
      expect(
        gridAfter!.height,
        greaterThan(120),
        reason:
            'Prescription Expanded area must not collapse when the keyboard opens. '
            'before=${gridBefore.height} after=${gridAfter.height}',
      );
      expect(
        gridAfter.bottom,
        lessThanOrEqualTo(keyboardTop + 1),
        reason: 'Editor must sit above the keyboard. grid=$gridAfter keyboardTop=$keyboardTop',
      );

      expect(amendRect, isNotNull);
      expect(
        amendRect!.bottom,
        lessThanOrEqualTo(keyboardTop + 1),
        reason:
            'Talk-or-type field must remain above the keyboard. '
            'amend=$amendRect keyboardTop=$keyboardTop',
      );
    },
  );
}
