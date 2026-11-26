import 'package:i_zerak_app/services/reminders/reminder_service.dart';

/// Un natif imaginaire : il garde ce qu'on lui transmet, et rend les
/// reponses donnees depuis les notifications.
class FakeReminderBridge implements IReminderBridge {
  FakeReminderBridge({this.supported = true});

  bool supported;
  final List<Map<String, Object?>> configs = [];
  List<String> pending = [];
  int notificationRequests = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<void> configure(Map<String, Object?> config) async => configs.add(config);

  @override
  Future<List<String>> takePendingSlotAnswers() async {
    final answers = pending;
    pending = [];
    return answers;
  }

  @override
  Future<bool> requestNotifications() async {
    notificationRequests++;
    return true;
  }
}
