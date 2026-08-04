import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note365_mobile/app/app.dart';
import 'package:note365_mobile/features/auth/presentation/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});

    // Mock local_auth platform channel responses for unit/widget tests
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable' ||
            methodCall.method == 'isDeviceSupported' ||
            methodCall.method == 'getAvailableBiometrics') {
          return false;
        }
        return false;
      },
    );
  });

  testWidgets('App boots into LoginScreen when unauthenticated', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: Practice121App()));
    await tester.pumpAndSettle();

    // Verify LoginScreen is rendered
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
