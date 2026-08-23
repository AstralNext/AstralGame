import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveAppVersion keeps versionName and drops default Android versionCode', () {
    expect(
      ClientRuntimeInfo.resolveAppVersion(
        version: '1.0.41',
        buildNumber: '1',
      ),
      '1.0.41',
    );
  });

  test('resolveAppVersion falls back to buildNumber when version is empty', () {
    expect(
      ClientRuntimeInfo.resolveAppVersion(
        version: '  ',
        buildNumber: '41',
      ),
      '41',
    );
  });
}
