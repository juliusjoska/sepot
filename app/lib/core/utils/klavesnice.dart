import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// PIN obrazovka má vlastní klávesnici, systémová nad ní nemá co dělat.
/// Při zamčení z otevřeného chatu (návrat z pozadí) ale pole psaní drží fokus
/// a iOS i Android klávesnici obnoví přes PIN — odemknout pak šlo jen
/// restartem appky.
void zavritKlavesnici() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}
