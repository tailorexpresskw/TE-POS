import 'dart:typed_data';

Future<String> installApp() async =>
    'Use the web app to install it from your browser.';
Future<String> deviceNotificationState() async =>
    '{"supported":false,"subscribed":false}';
Future<String> subscribeNotifications(String publicKey) async =>
    throw UnsupportedError('Use the web app for browser notifications.');
Future<String> currentPushSubscription() async => '';
Future<String> unsubscribeNotifications() async => '';
bool consumeNotificationOpen() => false;

void navigate(String url) {}
void openExternal(String url) {}
void download(String name, String text, [String type = 'text/csv']) {}
void printHtml(String html) {}
Future<({String name, String type, Uint8List bytes})?> pickFile() async => null;
