import 'package:astral_game/data/services/node_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('polls faster until virtual IP is assigned', () {
    expect(
      NodeManagementService.pollDelayFor(hasVirtualIp: false),
      const Duration(milliseconds: 500),
    );
    expect(
      NodeManagementService.pollDelayFor(hasVirtualIp: true),
      const Duration(seconds: 2),
    );
  });
}
