import 'package:astral_game/ui/widgets/shell_tab_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pages = [
  SizedBox(key: ValueKey('page0')),
  SizedBox(key: ValueKey('page1')),
  SizedBox(key: ValueKey('page2')),
];

Widget _harness(
  int index, {
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: direction,
        child: ShellTabStack(index: index, children: _pages),
      ),
    ),
  );
}

/// 页面在转场中的横向位移（占页面宽度的比例）。
double _pageDx(WidgetTester tester, String key) {
  final finder = find.ancestor(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(FractionalTranslation),
  );
  final widget = finder.evaluate().first.widget as FractionalTranslation;
  return widget.translation.dx;
}

void main() {
  testWidgets('首次访问的 Tab 从方向侧滑入，而不是硬切出现', (tester) async {
    await tester.pumpWidget(_harness(0));
    expect(find.byKey(const ValueKey('page0')), findsOneWidget);

    await tester.pumpWidget(_harness(1));

    final entering = find.byKey(const ValueKey('page1'));
    expect(entering, findsOneWidget);
    expect(_pageDx(tester, 'page1'), closeTo(0.022, 1e-6));

    await tester.pumpAndSettle();
    expect(_pageDx(tester, 'page1'), 0);
  });

  testWidgets('回到已访问的 Tab 时按反方向进场', (tester) async {
    await tester.pumpWidget(_harness(0));
    await tester.pumpWidget(_harness(1));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_harness(0));

    expect(_pageDx(tester, 'page0'), closeTo(-0.022, 1e-6));
    await tester.pumpAndSettle();
    expect(_pageDx(tester, 'page0'), 0);
  });

  testWidgets('RTL 下转场方向翻转', (tester) async {
    await tester.pumpWidget(_harness(0, direction: TextDirection.rtl));
    await tester.pumpWidget(_harness(1, direction: TextDirection.rtl));

    expect(_pageDx(tester, 'page1'), closeTo(-0.022, 1e-6));
    await tester.pumpAndSettle();
  });

  testWidgets('减少动态效果时不做横向位移', (tester) async {
    await tester.pumpWidget(
      _harness(0, disableAnimations: true),
    );
    await tester.pumpWidget(
      _harness(1, disableAnimations: true),
    );

    expect(_pageDx(tester, 'page1'), 0);
    await tester.pumpAndSettle();
  });
}
