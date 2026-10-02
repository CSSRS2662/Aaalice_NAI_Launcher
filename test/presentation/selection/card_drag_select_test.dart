import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/selection/card_drag_select.dart';
import 'package:nai_launcher/presentation/selection/card_selection.dart';
import 'package:nai_launcher/presentation/selection/card_selection_scope.dart';

class _Selection extends ChangeNotifier with CardSelectionCommands {
  SelectionModeState _state = const SelectionModeState();

  @override
  SelectionModeState get state => _state;

  @override
  set state(SelectionModeState value) {
    _state = value;
    notifyListeners();
  }
}

final _ids = [for (var i = 0; i < 30; i++) 'card-$i'];

/// Three columns of 100×100 cards whose long-press enters selection, like the
/// library cards do.
Widget _grid(_Selection selection) => MaterialApp(
  home: Scaffold(
    body: ListenableBuilder(
      listenable: selection,
      builder: (context, _) => CardSelectionScope(
        selection: selection.state,
        commands: selection,
        orderedIds: _ids,
        child: CardDragSelect(
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 1,
            children: [
              for (final id in _ids)
                CardDragSelectTarget(
                  id: id,
                  child: GestureDetector(
                    onLongPress: () => selection.enterAndSelect(id),
                    child: ColoredBox(
                      color: Colors.grey,
                      child: Center(child: Text(id)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'long-press then drag selects the range; dragging back trims it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(300, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selection = _Selection();
      await tester.pumpWidget(_grid(selection));

      final finger = await tester.startGesture(
        tester.getCenter(find.text('card-1')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(selection.state.selectedIds, {'card-1'});

      await finger.moveTo(tester.getCenter(find.text('card-7')));
      await tester.pump();
      expect(selection.state.selectedIds, {
        for (var i = 1; i <= 7; i++) 'card-$i',
      });

      await finger.moveTo(tester.getCenter(find.text('card-3')));
      await tester.pump();
      expect(selection.state.selectedIds, {'card-1', 'card-2', 'card-3'});

      await finger.up();
      await tester.pump();
      expect(selection.state.isActive, isTrue);
    },
  );

  testWidgets('a drag keeps cards selected before it began', (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selection = _Selection()
      ..enterAndSelect('card-0')
      ..select('card-5');
    await tester.pumpWidget(_grid(selection));

    final finger = await tester.startGesture(
      tester.getCenter(find.text('card-3')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await finger.moveTo(tester.getCenter(find.text('card-6')));
    await tester.pump();
    await finger.moveTo(tester.getCenter(find.text('card-3')));
    await tester.pump();
    await finger.up();

    expect(selection.state.selectedIds, {'card-0', 'card-3', 'card-5'});
  });

  testWidgets('scrolling first, or using a mouse, never drag-selects', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selection = _Selection()..enter();
    await tester.pumpWidget(_grid(selection));

    final scroll = await tester.startGesture(
      tester.getCenter(find.text('card-4')),
    );
    await scroll.moveBy(const Offset(0, -40));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await scroll.moveBy(const Offset(0, -100));
    await tester.pump();
    await scroll.up();
    await tester.pumpAndSettle();
    expect(selection.state.selectedIds, isEmpty);

    final mouse = await tester.startGesture(
      tester.getCenter(find.text('card-10')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await mouse.moveTo(tester.getCenter(find.text('card-12')));
    await tester.pump();
    await mouse.up();
    expect(selection.state.selectedIds, {'card-10'});
  });

  testWidgets('holding near the bottom edge scrolls and keeps extending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selection = _Selection();
    await tester.pumpWidget(_grid(selection));

    final finger = await tester.startGesture(
      tester.getCenter(find.text('card-0')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await finger.moveTo(const Offset(150, 590));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(selection.state.selectedIds.length, greaterThan(18));
    expect(selection.state.selectedIds, contains('card-0'));
  });
}
