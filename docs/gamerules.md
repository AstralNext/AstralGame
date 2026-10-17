# 游戏规则 JSON

调试：在仓库根或可执行文件旁自己建 `gamerules/`（已 gitignore，不要提交）。放入 `gamerules.json` 或任意 `.json` 后重启客户端；有文件则不再拉线上。可从 `assets/games/rules.json` 复制再改。

```json
{
  "version": 4,
  "games": [
    {
      "id": "raft",
      "name": "Raft",
      "name_zh": "木筏求生",
      "color": "#2A7F9E",
      "icon": "sailing",
      "steam_app_id": 648800,
      "sgdb_game_id": 18740,
      "icon_asset": "assets/games/raft/icon.png",
      "grid_asset": "assets/games/raft/grid.png",
      "show_in_picker": true,
      "sort": 20,
      "platforms": { "windows": { } }
    }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `id` | 英文 id；注入 DLL 在 `native/<id>/` |
| `name` | 英文显示名，默认 `id` |
| `name_zh` | 中文名；有则列表优先显示，可省略 |
| `description` | 选择器标题下方的短说明，可省略 |
| `color` | `#RRGGBB` |
| `icon` | Material Icons 名 |
| `steam_app_id` / `sgdb_game_id` | Steam / SteamGridDB |
| `icon_asset` / `grid_asset` | `assets/...` 或 `https://...` 或相对 `https://astral.fan/` 的 `games/...` |
| `show_in_picker` | 默认 `true` |
| `sort` | 越小越前，默认 `100` |
| `platforms` | 键：`windows` / `linux` / `android` / `ios` / `macos` |

## `platforms.windows`

```json
{
  "network": { "enable_udp_broadcast_relay": true, "protocol": "udp" },
  "lan_game_discover": { },
  "inject": { },
  "magic_wall": { },
  "forwards": []
}
```

| 字段 | 说明 |
|------|------|
| `enable_udp_broadcast_relay` | 本机 UDP 广播进虚拟网 |
| `protocol` | `tcp` / `udp`；不写默认 `udp`。决定 EasyTier `[flags]` 用哪一套 |
| `lan_game_discover` | 对象一条，数组多条 |
| `inject` | Unity Mono 注入 |
| `magic_wall` | 防火墙规则，按 exe 或全局（见下） |
| `forwards` | 手写 TCP 转发，多数游戏不用 |

Minecraft 写 `"protocol": "tcp"`。其它游戏不写则走 UDP 档。两套对应 EasyTier `[flags]` 的 QUIC/KCP 开关，不是改 `listeners`。

## `lan_game_discover`

| type | 字段 | 例子 |
|------|------|------|
| `udp_broadcast` | `port` `parser` | Raft `6489` / Valheim `2460`，只收本机包 |
| `udp_multicast` | `multicast` `parser` | `"224.0.2.60:4445"` |
| `udp_probe` | `probe` `parser` | `"fe01"` |
| `static_port` | `port` | 口被占用才宣告 |
| `process_udp` | `process` / `window` | 按进程取 UDP 口 |

可选：`id` `label` `title`（`{player}` `{game}` `{label}` `{motd}` `{map}`）`beacon_port`。

`parser`：`minecraft_motd` `mindustry_server` `scfa_lan` `raft_lan` `valheim_lan`。

```json
{ "type": "udp_broadcast", "port": 6489, "parser": "raft_lan", "title": "{player} * Astral" }
```

```json
{ "type": "udp_multicast", "multicast": "224.0.2.60:4445", "parser": "minecraft_motd" }
```

```json
{ "type": "udp_probe", "probe": "fe01", "parser": "mindustry_server", "multicast": "227.2.7.7:20151", "port": 6567 }
```

```json
{ "type": "static_port", "port": 24642 }
```

```json
{
  "type": "process_udp",
  "parser": "scfa_lan",
  "beacon_port": 15000,
  "process": ["game.exe", "ForgedAlliance.exe"],
  "window": ["Forged Alliance"]
}
```

## `inject`

```json
{
  "type": "mono",
  "process": ["valheim.exe"],
  "dll": "AstralValheimNet.dll",
  "namespace": "AstralValheimNet",
  "class": "Loader",
  "method": "Init",
  "delay_seconds": 8
}
```

`dll` 在 `native/<游戏id>/`。注入器 `native/inject/astral_mono_inject.exe`。

| 字段 | 默认 | 说明 |
|------|------|------|
| `type` | | 目前只有 `mono`（Unity Mono） |
| `process` | `[]` | 目标 exe 名，可多个；**必填**，没配不会注入 |
| `window` | `[]` | 预留字段，当前不参与匹配 |
| `dll` | | 注入的 DLL 文件名，放在 `native/<游戏id>/` |
| `namespace` / `class` | | 注入入口的类型 |
| `method` | `Init` | 注入调用的静态方法 |
| `delay_seconds` | `5` | 发现进程后等待多久再注入 |

## `magic_wall`

Windows 防火墙规则（WFP）。只有 `platforms.windows` 生效；进房时下发，出房时逐条撤销。

- **按进程**：只对指定 exe 的流量生效，进程启动后才套用
- **不按进程（全局）**：整机生效，进房立刻下发，不等任何进程

### 三种写法

**1. 按 exe 展开（最常用）**

```json
"magic_wall": {
  "valheim.exe": [
    { "action": "allow", "protocol": "udp", "direction": "both", "local_port": "2456" },
    { "action": "allow", "protocol": "udp", "direction": "both", "local_port": "2460" }
  ],
  "game.exe": [
    { "action": "allow", "protocol": "udp", "direction": "both", "local_port": "15000" }
  ]
}
```

键写成 `"*"` 表示这一组不针对进程（整机生效），可以和具体 exe 混写：

```json
"magic_wall": {
  "*": [
    { "action": "block", "protocol": "udp", "direction": "outbound", "remote_ip": "203.0.113.7", "remote_port": "443" }
  ],
  "valheim.exe": [
    { "action": "allow", "protocol": "udp", "direction": "both", "local_port": "2456" }
  ]
}
```

**2. `process` + `rules`**

```json
"magic_wall": {
  "enabled": true,
  "process": ["valheim.exe", "game.exe"],
  "rules": [
    { "action": "allow", "protocol": "udp", "direction": "both", "local_port": "2456" }
  ]
}
```

同一组 `rules` 会分别套到每个 exe 上。

**3. 数组形式（每项可各自带规则）**

```json
"magic_wall": [
  { "process": "valheim.exe", "rules": [{ "action": "allow", "protocol": "udp", "local_port": "2456" }] },
  { "process": "game.exe", "rules": [{ "action": "allow", "protocol": "tcp", "local_port": "15000" }] },
  "Raft.exe"
]
```

只写字符串表示该 exe 走默认放行（等价于空规则）。

数组里 `process` 写 `"*"` 就是全局项，可以和按进程的项混在一起：

```json
"magic_wall": [
  { "process": "*", "rules": [{ "action": "block", "protocol": "udp", "remote_port": "27015" }] },
  { "process": "valheim.exe", "rules": [{ "action": "allow", "protocol": "udp", "local_port": "2456" }] },
  "Raft.exe"
]
```

### 不针对进程（全局规则）

各写法的全局形式：

| 写法 | 全局怎么写 |
|------|-----------|
| 按 exe 展开 | 键写 `"*"`：`"*": [ ... ]` |
| `process` + `rules` | `"process": ["*"]`；或省掉 `process` 只给 `rules` |
| 数组形式 | `{ "process": "*", "rules": [ ... ] }` |
| 别名 | `*` / `all` / `any` / `全局` 等价 |

`process` 写 `*`、`all`、`any`、`全局` 任一值，即不绑定进程、规则整机生效：

```json
"magic_wall": {
  "enabled": true,
  "process": ["*"],
  "rules": [
    {
      "name": "屏蔽遥测",
      "action": "block",
      "protocol": "udp",
      "direction": "outbound",
      "remote_ip": "203.0.113.7",
      "remote_port": "443"
    }
  ]
}
```

也可省略 `process`，只给 `rules`，同样视为全局：

```json
"magic_wall": {
  "enabled": true,
  "rules": [{ "action": "block", "protocol": "tcp", "remote_port": "80" }]
}
```

数组形式里写 `{"process": "all", "rules": [...]}` 同样生效。

规则字段与按进程的规则完全一致，只是不带进程条件。

### 规则字段

| 字段 | 默认 | 说明 |
|------|------|------|
| `id` | 空 | 规则标识；不填按数组序号生成。同一游戏内唯一即可 |
| `name` | `allow` | 规则名（显示在防火墙过滤器里） |
| `enabled` | `true` | `false` 跳过该条 |
| `action` | `allow` | `allow` 允许 / `block` 阻止 |
| `protocol` | `both` | `tcp` / `udp` / `both` / `any`（`any` = 不限协议） |
| `direction` | `both` | `inbound` 入站 / `outbound` 出站 / `both` |
| `local_port` | 不限 | `"2456"` 或区间 `"2456-2460"` |
| `remote_port` | 不限 | 同上 |
| `local_ip` | 不限 | 单个 IP 或网段，如 `"100.100.100.5"`、`"100.100.100.0/24"`；支持 IPv6 |
| `remote_ip` | 不限 | 同上 |
| `description` | 空 | 备注 |

`protocol: both` 会按 TCP、UDP 各建一套；`direction: both` 再各建入站/出站；`protocol: any` 则不限协议，只按方向建。

地址族：不写 `local_ip`/`remote_ip` 时同时作用于 IPv4 与 IPv6；写了 IPv4 地址/网段就只作用于 IPv4，写了 IPv6 就只作用于 IPv6。同一条规则里 `local_ip` 与 `remote_ip` 不要一个 v4 一个 v6（会直接被拒绝）。

### 生效规则

- 全局规则：进房后立即下发，与进程是否存在无关
- 按进程规则：监视到目标 exe 启动后套用；同名 exe 从不同路径启动会各自套一份；同一路径只套一次
- 进程匹配按文件名（忽略目录和大小写），可省略 `.exe`（`"valheim"` 能匹配 `valheim.exe`）
- 某 exe **规则列表为空**（或只写 exe 名）→ 对该进程放行一切（默认 allow）
- **全局规则列表为空不会下发**，也不会产生"整机放行"，避免误放开
- 出房 / 停止房间辅助时，本房间下发的所有规则会被删除
- 不支持域名：先解析成 IP 或网段再写

### 注意事项

- 全局 `"action": "allow"` 会放开整台机器，谨慎使用
- 规则需要管理员权限（WFP 引擎 + 过滤器）
- 魔法墙只在 Windows 生效；其它平台字段会被忽略

## `forwards`

本机监听端口，把连接转发到虚拟网内的目标地址。进房时启动，出房时全部停止。

```json
"forwards": [
  { "listen": "0.0.0.0:25565", "target": "100.100.100.5:25565" },
  { "listen": "127.0.0.1:8080", "target": "100.100.100.8:80", "host_only": false }
]
```

| 字段 | 默认 | 说明 |
|------|------|------|
| `listen` | 必填 | `IP:端口`，本机监听地址；`0.0.0.0` 表示所有网卡 |
| `target` | 必填 | `IP:端口`，转发目标（通常是虚拟网内其它成员） |
| `proto` | `tcp` | 目前只支持 `tcp`，写其它值会被跳过 |
| `host_only` | `true` | 仅房主启动该转发；`false` 表示所有成员都启动 |

