import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only enabled idle servers are ping targets', () {
    final servers = [
      ServerMod(id: 1, name: 'a', url: 'tcp://1.1.1.1:1', enable: true),
      ServerMod(id: 2, name: 'b', url: 'tcp://2.2.2.2:1', enable: false),
      ServerMod(id: 3, name: 'c', url: 'tcp://3.3.3.3:1', enable: true),
    ];
    expect(
      serversEligibleForPing(servers).map((s) => s.id),
      [1, 3],
    );
    expect(
      serversEligibleForPing(servers, activeIds: {1}).map((s) => s.id),
      [3],
    );
  });
}
