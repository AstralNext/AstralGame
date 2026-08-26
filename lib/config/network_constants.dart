/// 网络层魔法常量统一管理，避免字符串散落到各业务文件里。
///
/// - IP/端口改一处全局生效；
/// - 注释保留每条常量的用途与来源；
/// - 带语义别名（如 [kScfaProxyReplyIpV4]）方便按业务搜索。

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

// --- SCFA / Forged Alliance 专属 ---

/// SCFA 加入方回包只用 127.0.0.1（避免 192.168.x 被游戏丢包）。
const kScfaProxyReplyIpV4 = kLoopbackIpV4;

/// SCFA 默认 LAN 广播代答口。
const kScfaDefaultBeaconPort = 15000;

// --- 广播地址 ---

/// IPv4 有限广播地址（255.255.255.255），用于 LAN 游戏发现。
const kBroadcastIpV4 = '255.255.255.255';

// --- 默认虚拟 IP ---

/// 默认虚拟 IP（ZeroTier 风格），用于本地虚拟网卡未配置时的回退值。
const kDefaultVirtualIpV4 = '10.147.18.24';

// --- 远程服务 ---

/// astral-share 短码服务地址。
const kShareCodeServiceBaseUrl = 'http://103.194.107.25:8080/';
