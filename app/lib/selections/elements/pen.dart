part of '../selection.dart';

class PenElementSelection extends ElementSelection<PenElement> {
  final _propertySelection = PenPropertySelection();

  PenElementSelection(super.selected);

  @override
  List<Widget> buildProperties(BuildContext context) {
    final element = selected.first.element;
    void updateProperty(PenProperty property) => updateElements(
      context,
      elements.map((e) => e.copyWith(property: property)).toList(),
    );
    return [
      ...super.buildProperties(context),
      if (_rooms case (final first, final second)) ...[
        _RoomMergeButtons(first: first, second: second),
        const SizedBox(height: 8),
      ],
      ..._propertySelection.build(context, element.property, updateProperty),
    ];
  }

  /// The two selected room fills, in selection order, if the selection is
  /// exactly two rooms.
  (PenElement, PenElement)? get _rooms {
    if (selected.length != 2) return null;
    final first = selected[0].element, second = selected[1].element;
    if (!isRoomFill(first) || !isRoomFill(second)) return null;
    return (first, second);
  }

  @override
  Selection insert(element) {
    if (element is Renderer<PenElement>) {
      return PenElementSelection([...selected, element]);
    }
    return super.insert(element);
  }

  @override
  PhosphorIconData icon({bool filled = false}) =>
      filled ? PhosphorIconsFill.pen : PhosphorIconsLight.pen;

  @override
  String getLocalizedName(BuildContext context) =>
      AppLocalizations.of(context).pen;
}

/// Combine and Subtract for two selected rooms.
class _RoomMergeButtons extends StatelessWidget {
  const _RoomMergeButtons({required this.first, required this.second});

  final PenElement first, second;

  void _merge(BuildContext context, {required bool subtract}) {
    final bloc = context.read<DocumentBloc>();
    final state = bloc.state;
    if (state is! DocumentLoadSuccess) return;
    final loc = AppLocalizations.of(context);
    final merged = mergeRooms(first, second, subtract: subtract);
    if (merged is MergeWithHole) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(loc.amazeRoomWithHole)));
      return;
    }
    final changes = mergeRoomChanges(
      content: state.page.content,
      first: first,
      second: second,
      subtract: subtract,
      roomName: loc.amazeRoomName,
      areaText: loc.amazeSquareFeet,
    );
    if (changes == null) return;
    bloc.add(ElementsChanged(changes));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('amaze-room-combine'),
          onPressed: () => _merge(context, subtract: false),
          icon: const PhosphorIcon(PhosphorIconsLight.unite),
          label: Text(loc.amazeCombine),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('amaze-room-subtract'),
          onPressed: () => _merge(context, subtract: true),
          icon: const PhosphorIcon(PhosphorIconsLight.subtract),
          label: Text(loc.amazeSubtract),
        ),
      ],
    );
  }
}
