import 'package:butterfly/cubits/settings.dart';

/// Settings flag that turns the aMaze editor shell on.
const kAmazeShellFlag = 'amazeShell';

/// Settings flag that keeps the classic Butterfly editor layout.
const kClassicEditorFlag = 'classicEditor';

/// Whether the aMaze shell is used when neither flag is set.
///
/// aMaze treats every platform the same, so the shell is always the default.
/// [kClassicEditorFlag] still switches back to the classic layout.
bool get amazeShellIsDefault => true;

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
