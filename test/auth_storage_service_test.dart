import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:note365_mobile/features/auth/data/models/auth_token.dart';
import 'package:note365_mobile/features/auth/data/services/auth_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthStorageService', () {
    late AuthStorageService storageService;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      storageService = const AuthStorageService(
        storage: FlutterSecureStorage(),
      );
    });

    test('saveAuthToken and getAuthToken round-trip', () async {
      const token = AuthToken(
        accessToken: 'access-123',
        refreshToken: 'refresh-456',
        accountId: 'acc-789',
        email: 'doctor@example.com',
        fullName: 'Dr. Smith',
        profileCompletionStatus: 'Completed',
      );

      await storageService.saveAuthToken(token);

      final retrieved = await storageService.getAuthToken();
      expect(retrieved, isNotNull);
      expect(retrieved!.accessToken, equals('access-123'));
      expect(retrieved.refreshToken, equals('refresh-456'));
      expect(retrieved.accountId, equals('acc-789'));
      expect(retrieved.email, equals('doctor@example.com'));
      expect(retrieved.fullName, equals('Dr. Smith'));
      expect(retrieved.profileCompletionStatus, equals('Completed'));
    });

    test('clearTokens removes stored token credentials', () async {
      const token = AuthToken(
        accessToken: 'access-123',
        refreshToken: 'refresh-456',
        accountId: 'acc-789',
        email: 'doctor@example.com',
        fullName: 'Dr. Smith',
        profileCompletionStatus: 'Completed',
      );

      await storageService.saveAuthToken(token);
      await storageService.clearTokens();

      final retrieved = await storageService.getAuthToken();
      expect(retrieved, isNull);
    });

    test('biometric preference toggle', () async {
      expect(await storageService.isBiometricEnabled(), isFalse);

      await storageService.setBiometricEnabled(true);
      expect(await storageService.isBiometricEnabled(), isTrue);

      await storageService.setBiometricEnabled(false);
      expect(await storageService.isBiometricEnabled(), isFalse);
    });
  });
}
