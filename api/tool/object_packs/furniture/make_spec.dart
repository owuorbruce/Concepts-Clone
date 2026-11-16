// Writes pack.json, the object pack spec of the furniture pack, from
// FloorPlanner's source/manifest.json.
//
// Usage, from api/: dart run tool/object_packs/furniture/make_spec.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final directory = File.fromUri(Platform.script).parent;
  final manifestFile = File('${directory.path}/source/manifest.json');
  final manifest = (jsonDecode(manifestFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final spec = {
    'id': 'furniture',
    'name': 'Furniture (to scale)',
    'description': 'Top-view furniture and fixtures at real size.',
    'author': 'FloorPlanner contributors',
    'license': 'CC0-1.0',
    'licenseUrl': 'https://creativecommons.org/publicdomain/zero/1.0/',
    'sourceUrl': 'https://github.com/pjm4github/FloorPlanner/tree/ce0c439/assets/furnishings',
    'version': '1.0.0',
    'sizing': 'inches',
    'objects': [
      for (final entry in manifest)
        {
          'name': entry['name'],
          'category': entry['category'],
          'file': 'source/${entry['file']}',
          'widthIn': entry['width_in'],
          'depthIn': entry['depth_in'],
          'furnishing': {
            'id': entry['id'],
            'heightIn': entry['height_in'],
            'elevationIn': entry['elevation_in'],
            'form': entry['form'],
            'material': entry['material'],
            'regionMaterial': entry['region_material'],
            'priceUsd': entry['price'],
          },
        },
    ],
  };
  final output = File('${directory.path}/pack.json');
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(spec)}\n',
  );
  stdout.writeln('Wrote ${output.path} with ${manifest.length} objects.');
}
