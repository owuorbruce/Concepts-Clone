import 'dart:io';

import 'package:butterfly/cubits/settings.dart';
import 'package:flutter/foundation.dart';

/// Settings flag that turns the aMaze editor shell on.
const kAmazeShellFlag = 'amazeShell';

/// Settings flag that keeps the classic Butterfly editor layout.
const kClassicEditorFlag = 'classicEditor';

/// Whether the aMaze shell is used when neither flag is set.
///
/// aMaze is Android-first, so the shell is the default there and on the web
/// preview. Other platforms opt in with [kAmazeShellFlag].
bool get amazeShellIsDefault => kIsWeb || Platform.isAndroid;

extension AmazeShellSettings on ButterflySettings {
  /// Whether the editor should use the aMaze shell.
  bool get usesAmazeShell {
    if (hasFlag(kClassicEditorFlag)) return false;
    return hasFlag(kAmazeShellFlag) || amazeShellIsDefault;
  }

  /// Whether the app bar floats over the canvas on wide screens.
  bool get usesFloatingEditor => hasFlag('floatingEditor') || usesAmazeShell;

  /// Whether tools are shown inline in the app bar; the aMaze shell uses the
  /// tool wheel instead.
  bool get usesInlineTools => isInline && !usesAmazeShell;
}
