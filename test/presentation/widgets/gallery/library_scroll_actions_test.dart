import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/gallery/library_scroll_actions.dart';

Widget _list({
  required int count,
  VoidCallback? onLoadMore,
  bool canLoadMore = true,
  Future<void> Function()? onRefresh,
}) => MaterialApp(
  home: Scaffold(
    body: LibraryScrollActions(
      onLoadMore: onLoadMore,
      canLoadMore: canLoadMore,
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: count,
        itemBuilder: (context, index) =>
            SizedBox(height: 100, child: Text('item $index')),
      ),
    ),
  ),
);

void main() {
  testWidgets('loads more when the loaded items do not fill the screen', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(_list(count: 3, onLoadMore: () => loads++));
    await tester.pump();
    expect(loads, greaterThan(0));
  });

  testWidgets('loads more only near the end, and never without more', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(_list(count: 60, onLoadMore: () => loads++));
    await tester.pump();
    expect(loads, 0, reason: 'far from the end');

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(loads, 0, reason: 'still more than a screenful below');

    await tester.drag(find.byType(ListView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(loads, greaterThan(0));

    var blocked = 0;
    await tester.pumpWidget(
      _list(count: 3, onLoadMore: () => blocked++, canLoadMore: false),
    );
    await tester.pump();
    expect(blocked, 0);
  });

  testWidgets('pulling down from the top refreshes, even a short list', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      _list(count: 2, canLoadMore: false, onRefresh: () async => refreshes++),
    );
    await tester.fling(find.text('item 0'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });
}
