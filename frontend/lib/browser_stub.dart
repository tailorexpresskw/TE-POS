import 'dart:typed_data';

void navigate(String url) {}
void download(String name, String text, [String type = 'text/csv']) {}
void printHtml(String html) {}
Future<({String name, String type, Uint8List bytes})?> pickFile() async => null;
