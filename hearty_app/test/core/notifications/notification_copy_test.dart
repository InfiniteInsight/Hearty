import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/notifications/notification_service.dart';

void main() {
  test('follow-up notification body tells the user it will listen', () {
    expect(NotificationService.followUpBody.toLowerCase(), contains('listen'));
  });
}
