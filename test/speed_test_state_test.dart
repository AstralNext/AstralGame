import 'package:astral_game/data/models/speed_test_node.dart';
import 'package:astral_game/data/services/speed_test_service.dart';
import 'package:astral_game/data/state/speed_test_state.dart';
import 'package:flutter_test/flutter_test.dart';

SpeedTestNode _node({
  required String ip,
  required String province,
  required String city,
  required String operator,
}) => SpeedTestNode(
  ip: ip,
  port: '65499',
  name: '$province$operator',
  province: province,
  city: city,
  operator: operator,
);

void main() {
  late SpeedTestState state;

  setUp(() {
    state = SpeedTestState(SpeedTestService());
    state.nodes.value = [
      _node(ip: '10.0.0.1', province: '北京', city: '北京', operator: '联通'),
      _node(ip: '10.0.0.2', province: '山东', city: '济南', operator: '电信'),
      _node(ip: '10.0.0.3', province: '山东', city: '济南', operator: '移动'),
      _node(ip: '10.0.0.4', province: '山东', city: '青岛', operator: '电信'),
    ];
  });

  test('同省同运营商优先', () {
    state.applyLocalDefaults(localProvince: '山东', localIsp: '中国电信');
    expect(state.selected.value?.ip, '10.0.0.2');
  });

  test('只有运营商匹配时用同运营商节点', () {
    state.applyLocalDefaults(localProvince: '广东', localIsp: '电信');
    expect(state.selected.value?.ip, '10.0.0.2');
  });

  test('只有省份匹配时用同省节点', () {
    state.applyLocalDefaults(localProvince: '山东', localIsp: '广电');
    expect(state.selected.value?.ip, '10.0.0.2');
  });

  test('归属地完全匹配不上时取节点表第一个', () {
    state.applyLocalDefaults(localProvince: '广东', localIsp: '广电');
    expect(state.selected.value?.ip, '10.0.0.1');
  });

  test('归属地为空时不改动默认选中', () {
    state.selected.value = state.nodes.value.last;
    state.applyLocalDefaults(localProvince: '', localIsp: '');
    expect(state.selected.value?.ip, '10.0.0.4');
  });

  test('归属地默认值只生效一次，用户改选后不再覆盖', () {
    state.applyLocalDefaults(localProvince: '山东', localIsp: '电信');
    state.selectNode(state.nodes.value.first);
    state.applyLocalDefaults(localProvince: '北京', localIsp: '联通');
    expect(state.selected.value?.ip, '10.0.0.1');
  });
}
