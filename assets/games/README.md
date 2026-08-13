# 游戏规则

线上数据源（完整目录）：`https://astral.fan/gamerules.json`  
仓库路径：[`ldoubil/astral.github.io` → `public/gamerules.json`](https://github.com/ldoubil/astral.github.io/blob/main/public/gamerules.json)  
本地 `assets/games/rules.json`：**仅通用回退**（如「其他」），不含具体游戏配置。

## 结构

游戏根级放目录元数据（`id` / `name` / `color` / `icon_asset` / `grid_asset` / …）。  
平台相关配置写在 `platforms.<os>` 下：

```json
"platforms": {
  "windows": {
    "network": { "enable_udp_broadcast_relay": false },
    "lan_game_discover": { "...": "..." },
    "magic_wall": { "...": "..." },
    "forwards": []
  }
}
```

## 图片字段 `icon_asset` / `grid_asset`

| 写法 | 含义 |
|------|------|
| `https://...` | 网络绝对地址（推荐） |
| `games/...` 或 `/games/...` | 相对 `https://astral.fan/` 解析 |
| `assets/...` | 应用内 asset（本地一般不用） |

## `lan_game_discover`

主干：**发现 → 虚拟 IP 绑定 → ET 宣告 → 房间列表**。  
新游戏优先只改 JSON；只有出现全新协议时才加通用 `type` / `parser`。

| type | 含义 | 典型字段 |
|------|------|----------|
| `static_port` | 固定端口宣告（默认真听端口才显示） | `port`；`params.require_listening`（默认 true） |
| `udp_multicast` | 听 UDP 组播再解析 | `multicast` / `multicast_port` / `parser` |
| `udp_probe` | 主动发探测包再解析回复 | `probe_hex` / `parser` / `multicast`? / `port`? |

| parser | 侧 | 游戏 |
|--------|----|------|
| `minecraft_motd` | 内核听 / Dart 重建 | MC `[MOTD]…[/MOTD][AD]port[/AD]` |
| `mindustry_server` | Dart | Mindustry `NetworkIO.writeServerData()` |

### `params`：标题重建 + 本机注入（通用）

任意 `type` 都可加，不绑死某一款游戏。  
**启停跟开放游戏事件走**：`game.advertiseOpen` 出现条目 → 开组播注入 + 转发；广告消失 / TTL 到期 / 退房 → 立刻停。

| 字段 | 含义 |
|------|------|
| `title_template` | 重建标题：`{player}` `{game}` `{label}` `{motd}` |
| `inject_local` | 向本机回环发 UDP 宣告载荷 |
| `inject_bind` | 默认 `127.0.0.1`（游戏会连这个 IP） |
| `inject_mode` | `loopback` / `multicast` / `both`（默认 both） |
| `forward_local` | `127.0.0.1:游戏端口` TCP 转到对端虚拟 IP |

新 parser 只需补「解析 + 重建载荷」，不必新发现器。

### Minecraft 示例

```json
{
  "id": "mc",
  "label": "Minecraft",
  "type": "udp_multicast",
  "multicast": "224.0.2.60",
  "multicast_port": 4445,
  "parser": "minecraft_motd",
  "params": {
    "title_template": "{player} · {game}",
    "inject_local": true,
    "inject_bind": "127.0.0.1",
    "forward_local": true
  }
}
```

房主开局域网世界 → Astral 听 MOTD，标题改成「玩家名 · Minecraft」再经 ET 发出。  
客人：本机 `127.0.0.1` 注入宣告 + TCP 转到房主虚拟 IP；MC 多人游戏里直接点 LAN。

### Mindustry 示例（配置驱动）

```json
{
  "id": "mindustry",
  "label": "Mindustry",
  "type": "udp_probe",
  "probe_hex": "fe01",
  "parser": "mindustry_server",
  "multicast": "227.2.7.7",
  "multicast_port": 20151,
  "port": 6567
}
```

`probe_hex: "fe01"` = KryoNet/Arc `DiscoverHost`（字节 `[-2, 1]`）。

### Stardew Valley（无原生局域网扫描）

原版需在 Co-op → Join LAN Game **手动输入 IP**；默认游戏端口 **UDP 24642**。  
Astral 用 `static_port` 把虚拟 IP:24642 宣告到房间，同伴复制后填入游戏即可（与泰拉同类）。  
默认会检测本机 **UDP 24642 是否在听**：关主机后几秒内列表会消失。

```json
{
  "id": "stardew",
  "label": "Stardew Valley",
  "type": "static_port",
  "port": 24642
}
```

ET：`game.advertiseOpen` / `game.listOpen`。
