# 游戏规则 JSON

调试：在仓库根或可执行文件旁自己建 `gamerules/`（已 gitignore，不要提交）。放入 `gamerules.json` 或任意 `.json` 后重启客户端；有文件则不再拉线上。可从 `assets/games/rules.json` 复制再改。

```json
{
  "version": 4,
  "games": [
    {
      "id": "raft",
      "name": "Raft",
      "description": "进房后在游戏里搜局域网房间",
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
| `name` | 显示名，默认 `id` |
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
| `magic_wall` | 按 exe 独立防火墙规则 |
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

## `magic_wall`

按进程文件名写防火墙规则，每个 exe 一套。

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

| 字段 | 默认 | 说明 |
|------|------|------|
| `action` | `allow` | `allow` / `block` |
| `protocol` | `both` | `tcp` / `udp` / `both` / `any` |
| `direction` | `both` | `inbound` / `outbound` / `both` |
| `local_port` | | `"2456"` 或 `"2456-2460"` |
| `remote_port` | | 同上 |
| `local_ip` / `remote_ip` | | IP 或网段 |
| `name` | `allow` | 名称 |
