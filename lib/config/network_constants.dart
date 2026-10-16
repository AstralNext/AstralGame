/// 网络层魔法常量统一管理，避免字符串散落到各业务文件里。
///
/// - IP/端口改一处全局生效；
/// - 注释保留每条常量的用途与来源；
/// - 带语义别名（如 [kScfaProxyReplyIpV4]）方便按业务搜索。
library;

// --- 本机地址 ---

/// IPv4 环回：127.0.0.1。
const kLoopbackIpV4 = '127.0.0.1';

/// IPv6 环回：::1。
const kLoopbackIpV6 = '::1';

/// 常用环回判断用集合。
const kLoopbackIpSet = <String>{kLoopbackIpV4, kLoopbackIpV6, 'localhost'};

/// IPv4 未指定（监听所有网卡）：0.0.0.0。
const kUnspecifiedIpV4 = '0.0.0.0';

/// IPv6 未指定（监听所有网卡）：::。
const kUnspecifiedIpV6 = '::';

/// 常用未指定判断用集合。
const kUnspecifiedIpSet = <String>{kUnspecifiedIpV4, kUnspecifiedIpV6};

// --- 组播默认值 ---

/// Minecraft / 通用默认 LAN 组播地址（老 MC 注册的保留组播）。
const kDefaultLanMulticastIpV4 = '224.0.2.60';

/// 对应 [kDefaultLanMulticastIpV4] 的默认端口。
const kDefaultLanMulticastPort = 4445;

/// 组合成 `host:port` 用于日志展示。
String get kDefaultLanMulticastEndpoint =>
    '$kDefaultLanMulticastIpV4:$kDefaultLanMulticastPort';

// --- EasyTier ---

/// EasyTier peer 默认监听端口；URL 未显式带端口时作为 TCP 探测目标端口。
const kEasyTierDefaultPort = 11010;

// --- SCFA / Forged Alliance 专属 ---

/// SCFA 加入方回包只用 127.0.0.1（避免 192.168.x 被游戏丢包）。
const kScfaProxyReplyIpV4 = kLoopbackIpV4;

/// SCFA 默认 LAN 广播代答口。
const kScfaDefaultBeaconPort = 15000;

// --- 广播地址 ---

/// IPv4 有限广播地址（255.255.255.255），用于 LAN 游戏发现。
const kBroadcastIpV4 = '255.255.255.255';

// --- 虚拟 IP 输入示例 ---

/// 手动填写虚拟 IPv4 的输入示例（仅作输入提示；默认留空，由用户自行填写并记忆）。
const kVirtualIpV4Example = '10.1.1.1/24';

/// 手动填写虚拟 IPv6 的输入示例（仅作输入提示；默认留空，由用户自行填写并记忆）。
const kVirtualIpV6Example = 'fd00::1/120';

// --- 房间虚拟网段（DHCP 初始网段） ---

/// 建房时 EasyTier DHCP 的初始 IPv4 网段。
///
/// EasyTier 的 `dhcp` 字段接受 bool 或 CIDR 字符串；显式给网段可避开默认的
/// `10.126.126.0/24`，也远离家用常见的 10.x / 192.168.x。前缀需 ≤30。
const kRoomDhcpIpv4Cidr = '100.100.100.0/24';

/// 建房时 EasyTier DHCPv6 的初始 IPv6 网段（ULA，须落在 `fc00::/7` 内且前缀 ≤126）。
const kRoomDhcpIpv6Cidr = 'fdae::/120';

const kSpeedTestConfigHost = 'https://dlcv2.cnspeedtest.cn:8443';

const kSpeedTestConfigPhp =
    '$kSpeedTestConfigHost/TaierAndroid/Config/ConfigMD5.php';

const kSpeedTestApp = 'globalspeed';

const kSpeedTestPkg = 'com.cnspeedtest.globalspeed';

const kSpeedTestRandToken = '12345555';

const kSpeedTestDefaultPort = 65499;

const kSpeedTestReportBandwidth = 200;

const kSpeedTestDesKey = r'dw!@#$%^';

const kSpeedTestFetchTimeout = Duration(seconds: 25);

const kSpeedTestDovalidTimeout = Duration(seconds: 4);

const kSpeedTestProbeTimeout = Duration(seconds: 2);

const kSpeedTestProbeSamples = 3;

const kSpeedTestLatencyProbeInterval = Duration(milliseconds: 800);

const kSpeedTestWindow = Duration(seconds: 4);

const kSpeedTestThreads = 4;

// --- 远程服务 ---

/// astral-share 短码服务地址。
const kShareCodeServiceBaseUrl = 'http://103.194.107.25:8080/';

/// SmartDNS 配置（`smartdns.conf`）的远端下发地址，与 gamerules.json 同域。
///
/// 客户端只在网络加速已启用时同步；远端内容要过 `looksLikeSmartDnsConf` 校验，
/// 部署失败由 auto_dns_binder 回滚到上一版。
const kSmartDnsConfUrl = 'https://next.astral.fan/smartdns.conf';

/// astral-share 短码服务请求超时：短码只是锦上添花（有离线邀请兜底），
/// 不能让建房/分享等关键路径被无超时请求无限挂起。
const kShareCodeTimeout = Duration(seconds: 8);

// --- 远程服务超时 ---
// 各远程 HTTP 服务的超时统一收口在此，改一处全局生效。

/// 一言（v1.hitokoto.cn）：装饰性内容，超时短一点无所谓。
const kHitokotoTimeout = Duration(seconds: 6);

/// 栗次元壁纸 JSON API（t.alcy.cc）：取直链，失败回退本地图。
const kWallpaperTimeout = Duration(seconds: 8);

/// 壁纸图片本体下载（可能是数 MB 的大图，比 JSON API 宽松）。
const kWallpaperDownloadTimeout = Duration(seconds: 30);

/// ISP 归属查询（myip.ipip.net）：失败显示「未知运营商」。
const kIspInfoTimeout = Duration(seconds: 8);

/// 游戏规则目录（gamerules.json）：有 asset/磁盘缓存多级回退。
const kGameRulesTimeout = Duration(seconds: 12);

/// SmartDNS 配置下发（smartdns.conf）：启动时同步一次，失败就保留本地配置。
const kSmartDnsConfTimeout = Duration(seconds: 10);

/// GitHub Releases 更新检查：GitHub 在国内访问慢，给最宽时限。
const kUpdateCheckTimeout = Duration(seconds: 15);
