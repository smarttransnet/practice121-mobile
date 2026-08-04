import 'package:flutter_test/flutter_test.dart';
import 'package:note365_mobile/features/transcription/data/services/note_sms_service.dart';
import 'package:note365_mobile/features/transcription/presentation/controllers/transcription_state.dart';

void main() {
  group('NoteSmsService & State', () {
    test('TranscriptionState isSendingSms defaults to false and copyWith works', () {
      const state = TranscriptionState();
      expect(state.isSendingSms, isFalse);

      final sendingState = state.copyWith(isSendingSms: true);
      expect(sendingState.isSendingSms, isTrue);

      final resetState = sendingState.copyWith(isSendingSms: false);
      expect(resetState.isSendingSms, isFalse);
    });

    test('NoteSmsService instantiation', () {
      final smsService = NoteSmsService();
      expect(smsService, isA<NoteSmsService>());
    });
  });
}
