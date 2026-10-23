import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/push/push_service.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/proto/sepot.pb.dart' as pb;

/// iPhony relayi neposílaly APNs ani VoIP token: init lokálních notifikací
/// na iOS házel výjimku, ta zastavila registraci u Apple a restoreMode ji
/// spolkl. Tady se hlídá pořadí kroků a skládání registrace bez iPhonu.
class _FakeMessaging extends MessagingService {
  _FakeMessaging() : super(storage: SecureStorageService());

  final registrations = <pb.RegisterPush>[];

  @override
  void registerPush(pb.RegisterPush registration) =>
      registrations.add(registration);
}

class _FakeIos extends IosPushPlatform {
  _FakeIos({
    this.apns,
    this.voip,
    this.permissionFails = false,
    this.registerFails = false,
  });

  final String? apns;
  final String? voip;
  final bool permissionFails;
  final bool registerFails;
  final calls = <String>[];
  bool? failedFlag;
  String? mode;

  @override
  bool get isIOS => true;

  @override
  Future<void> registerApns() async {
    calls.add('register');
    if (registerFails) throw StateError('apns channel');
  }

  @override
  Future<String?> apnsToken() async => apns;

  @override
  Future<String?> voipToken() async => voip;

  @override
  Future<void> requestPermission() async {
    calls.add('permission');
    if (permissionFails) {
      throw ArgumentError('iOS settings must be set');
    }
  }

  @override
  Future<void> writeMode(String m) async => mode = m;

  @override
  Future<void> setRegistrationFailed(bool failed) async => failedFlag = failed;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  String text(List<int> bytes) => utf8.decode(bytes);

  group('apnsRegistration', () {
    test('APNs i VoIP v jedné registraci', () {
      final reg = PushService.apnsRegistration(
        apnsToken: 'ab12',
        voipToken: 'cd34',
      )!;
      expect(reg.platform, pb.RegisterPush_Platform.PLATFORM_APNS);
      expect(text(reg.endpoint), 'ab12');
      expect(text(reg.voipToken), 'cd34');
    });

    test('samotný VoIP token jde s prázdným endpointem', () {
      final reg = PushService.apnsRegistration(voipToken: 'cd34')!;
      expect(reg.platform, pb.RegisterPush_Platform.PLATFORM_APNS);
      expect(reg.endpoint, isEmpty);
      expect(text(reg.voipToken), 'cd34');
    });

    test('bez tokenů se nic neposílá', () {
      expect(PushService.apnsRegistration(), isNull);
    });
  });

  test(
    'selhané oprávnění nezastaví registraci u Apple ani token pro relay',
    () async {
      final messaging = _FakeMessaging();
      final ios = _FakeIos(apns: 'ab12', voip: 'cd34', permissionFails: true);
      await PushService(messaging, ios: ios).restoreMode();

      expect(ios.calls, [
        'register',
        'permission',
      ], reason: 'registrace u Apple před dotazem na oprávnění');
      expect(ios.mode, 'apns');
      expect(ios.failedFlag, isFalse);
      final reg = messaging.registrations.single;
      expect(text(reg.endpoint), 'ab12');
      expect(text(reg.voipToken), 'cd34');
    },
  );

  test('VoIP token odejde, i když APNs token ještě nepřišel', () async {
    final messaging = _FakeMessaging();
    final push = PushService(messaging, ios: _FakeIos(voip: 'cd34'));
    await push.refreshVoipToken();
    final reg = messaging.registrations.single;
    expect(reg.endpoint, isEmpty);
    expect(text(reg.voipToken), 'cd34');
  });

  test('selhaná registrace se nespolkne — stav pushů ukáže chybu', () async {
    final ios = _FakeIos(registerFails: true);
    await PushService(_FakeMessaging(), ios: ios).restoreMode();
    expect(ios.failedFlag, isTrue);
  });
}
