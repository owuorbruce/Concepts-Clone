// Builds an object pack from a spec.
//
// Usage, from api/:
//   dart run tool/build_object_pack.dart <spec.json> <output.bfly>
//
// See tool/object_packs/README.md for the spec format.
import 'dart:io';

import 'object_pack_builder.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/build_object_pack.dart <spec.json> <output.bfly>',
    );
    exitCode = 64;
    return;
  }
  final BuildResult result;
  try {
    result = await buildObjectPack(File(args[0]));
  } on ObjectPackBuildException catch (e) {
    stderr.writeln('Build failed: $e');
    exitCode = 1;
    return;
  }
  final output = File(args[1]);
  await output.parent.create(recursive: true);
  final bytes = result.bytes;
  await output.writeAsBytes(bytes);
  for (final warning in result.warnings) {
    stdout.writeln('Warning: $warning');
  }
  stdout
    ..writeln('Objects: ${result.objectCount}')
    ..writeln('Size: ${bytes.length} bytes')
    ..writeln('Warnings: ${result.warnings.length}')
    ..writeln('Wrote ${output.path}');
}
