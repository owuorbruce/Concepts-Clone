# Object packs

An object pack is a Butterfly pack (`.bfly`) whose components are objects for
the Objects panel. Each object is one SVG drawn at a known size. Packs are
built from a JSON spec:

```sh
cd api
dart run tool/build_object_pack.dart <spec.json> <output.bfly>
```

## The spec

The spec is a JSON object with these fields:

- `id`: a short identifier, stored in every element so the pack it came from
  is known.
- `name`: the pack name shown in the Objects panel.
- `description`: one sentence about the pack.
- `author`: who made the drawings.
- `license`: the license as an SPDX identifier, for example `CC0-1.0`.
- `licenseUrl`: a link to the license text.
- `sourceUrl`: where the drawings come from.
- `version`: the pack version, for example `1.0.0`.
- `sizing`: how objects are sized, `inches` or `longestSide` (see below).
- `longestSideIn`: for `longestSide` sizing, the length of each object's
  longest side in inches.
- `objects`: the list of objects, in the order they appear in the pack.

Each object has:

- `name`: the name on the tile.
- `category` (optional): the heading the object is shown under. The
  component is named `<category> — <name>`, or just `<name>` without one.
  Names must be unique in a pack.
- `file`: the SVG, relative to the spec file.
- `widthIn` and `depthIn`: for `inches` sizing, the object's real width and
  depth in inches.
- `furnishing` (optional): extra facts about a piece of furniture. It is
  copied as is into the element's `extra.furnishing`, together with
  `widthIn` and `depthIn`.

## Sizing

One inch is 96 canvas units.

| `sizing`      | Size of the object                                                        |
| ------------- | ------------------------------------------------------------------------- |
| `inches`      | `widthIn × 96` by `depthIn × 96` canvas units                             |
| `longestSide` | Keeps the SVG's aspect ratio; its longest side is `longestSideIn × 96` |

For `inches`, the builder also reads the SVG's `viewBox`. If its width or
height differs from `widthIn` or `depthIn` by more than 0.5, it prints a
warning and uses the spec's numbers.

## Checks

The build fails, naming the file, if an SVG is missing, larger than 1 MB, not
well-formed XML, contains `<script` or `<foreignObject`, or links (`href` or
`xlink:href`) to anything other than `#…` or `data:image/…`. A duplicate
component name also fails the build.

The output is deterministic: building the same spec twice gives identical
components.

## Packs

- `furniture/`: Furniture (to scale), FloorPlanner's 96 top-view furniture
  and fixture symbols (CC0 1.0). `make_spec.dart` writes its `pack.json` from
  `source/manifest.json`.
