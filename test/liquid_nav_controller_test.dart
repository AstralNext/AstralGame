import 'package:astral_game/ui/widgets/navigation/liquid_nav.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LiquidNavController build({
    int count = 4,
    int initialIndex = 0,
    void Function(int)? onSelected,
  }) {
    final controller = LiquidNavController(
      vsync: const TestVSync(),
      count: count,
      initialIndex: initialIndex,
      onSelected: onSelected ?? (_) {},
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('重按当前项仍上报给上层，但位置不变', () {
    final selected = <int>[];
    final controller = build(initialIndex: 2, onSelected: selected.add);

    controller.tap(2);

    expect(selected, [2]);
    expect(controller.position.value, 2);
    expect(controller.currentIndex, 2);
  });

  test('点击其他项上报新索引，不自行改选中项', () {
    final selected = <int>[];
    final controller = build(initialIndex: 1, onSelected: selected.add);

    controller.tap(3);

    expect(selected, [3]);
    expect(controller.currentIndex, 1);
  });

  test('外部切换选中项只驱动动画，不重复上报', () {
    var calls = 0;
    final controller = build(onSelected: (_) => calls++);

    controller.updateSelection(3);
    controller.updateSelection(3);

    expect(controller.currentIndex, 3);
    expect(calls, 0);
  });

  test('开始拖拽会清掉按下态，并让指示器跟手', () {
    final controller = build();

    controller.setPressed(2, true);
    expect(controller.pressedIndex, 2);

    controller.beginDrag(1.25);

    expect(controller.pressedIndex, isNull);
    expect(controller.dragging, isTrue);
    expect(controller.position.value, closeTo(1.25, 1e-9));
    // 抬起程度由弹簧驱动，这里只验证弹簧已启动。
    expect(controller.lift.isAnimating, isTrue);
  });

  test('拖到首尾之外只保留少量橡皮筋溢出', () {
    final controller = build(initialIndex: 1);

    controller.beginDrag(-5);
    expect(controller.position.value, closeTo(-0.18, 1e-9));

    controller.updateDrag(9);
    expect(controller.position.value, closeTo(3.18, 1e-9));
    // 绘制位置另有 clamp，避免过冲跑到相邻布局之外。
    expect(controller.renderPosition, lessThanOrEqualTo(3.25));
  });

  test('松手吸附到最近项且只上报一次', () {
    final selected = <int>[];
    final controller = build(onSelected: selected.add);

    controller.beginDrag(2.4);
    controller.endDrag(0);

    expect(controller.dragging, isFalse);
    expect(controller.currentIndex, 2);
    expect(selected, [2]);
  });

  test('拖回原项不触发页面切换', () {
    final selected = <int>[];
    final controller = build(initialIndex: 1, onSelected: selected.add);

    controller.beginDrag(1.3);
    controller.endDrag(0);

    expect(controller.currentIndex, 1);
    expect(selected, isEmpty);
  });

  test('减少动态效果时位置瞬时收敛、不产生液态形变', () {
    final selected = <int>[];
    final controller = build(onSelected: selected.add);
    controller.reduceMotion = true;

    controller.beginDrag(-5);
    expect(controller.position.value, 0);
    expect(controller.liquidAmount, 0);
    expect(controller.velocityRatio, 0);
    expect(controller.liftAmount, 0);

    controller.updateDrag(4);
    expect(controller.position.value, 3);

    controller.endDrag(2);
    expect(controller.currentIndex, 3);
    expect(selected, [3]);
  });

  test('单页导航拖拽不会移动指示器', () {
    final controller = build(count: 1);

    controller.beginDrag(3);

    expect(controller.dragging, isFalse);
    expect(controller.position.value, 0);
  });
}
