import 'package:astral_game/data/services/windows_time_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseRegSzValue reads NtpServer and Type', () {
    const stdout = '''
HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\W32Time\\Parameters

    ServiceDll    REG_EXPAND_SZ    %systemroot%\\system32\\w32time.dll
    Type    REG_SZ    NTP
    NtpServer    REG_SZ    time.windows.com,0x9
''';
    expect(parseRegSzValue(stdout, 'Type'), 'NTP');
    expect(parseRegSzValue(stdout, 'NtpServer'), 'time.windows.com,0x9');
    expect(parseRegSzValue(stdout, 'Missing'), isNull);
  });

  test('ntpHostFromPeerList strips flags and extra peers', () {
    expect(ntpHostFromPeerList('pool.ntp.org,0x9'), 'pool.ntp.org');
    expect(
      ntpHostFromPeerList('pool.ntp.org,0x8 time.windows.com,0x9'),
      'pool.ntp.org',
    );
    expect(ntpHostFromPeerList('  '), isNull);
  });

  test('alreadyUsingAliyunNtp requires NTP type and aliyun host', () {
    expect(
      alreadyUsingAliyunNtp(ntpServer: 'pool.ntp.org,0x9', type: 'NTP'),
      isTrue,
    );
    expect(
      alreadyUsingAliyunNtp(ntpServer: 'pool.ntp.org,0x9', type: 'NT5DS'),
      isFalse,
    );
    expect(
      alreadyUsingAliyunNtp(ntpServer: 'time.windows.com,0x9', type: 'NTP'),
      isFalse,
    );
  });
}
