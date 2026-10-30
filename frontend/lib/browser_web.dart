import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void navigate(String url) {
  web.window.location.href = url;
}

void download(String name, String text, [String type = 'text/csv']) {
  final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  (web.HTMLAnchorElement()
        ..href = url
        ..download = name)
      .click();
  Timer(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
}

void printHtml(String html) {
  final blob = web.Blob(
    [html.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
}

Future<({String name, String type, Uint8List bytes})?> pickFile() async {
  final completer = Completer<({String name, String type, Uint8List bytes})?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.pdf,.jpg,.jpeg,.png,.webp';
  input.addEventListener(
    'cancel',
    ((web.Event e) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );
  Future<void> readFile() async {
    final file = input.files?.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    try {
      final data = await file.arrayBuffer().toDart;
      completer.complete((
        name: file.name,
        type: file.type,
        bytes: data.toDart.asUint8List(),
      ));
    } catch (e) {
      completer.completeError(e);
    }
  }

  input.addEventListener(
    'change',
    ((web.Event e) {
      unawaited(readFile());
    }).toJS,
  );
  input.click();
  return completer.future;
}
