import 'dart:html' as html;

bool _beforeUnloadAttached = false;

void attachBeforeUnloadWarning(String message) {
  if (_beforeUnloadAttached) {
    return;
  }

  html.window.onBeforeUnload.listen((event) {
    (event as html.BeforeUnloadEvent).returnValue = message;
  });
  _beforeUnloadAttached = true;
}
