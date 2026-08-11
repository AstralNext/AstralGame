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
| `static_port` | 固定端口宣告 | `port` |
| `udp_multicast` | 听 UDP 组播再解析 | `multicast` / `multicast_port` / `parser` |
| `udp_probe` | 主动发探测包再解析回复 | `probe_hex` / `parser` / `multicast`? / `port`? |

| parser | 侧 | 游戏 |
|--------|----|------|
| `minecraft_motd` | 内核 | MC `[MOTD]…[/MOTD][AD]port[/AD]` |
| `mindustry_server` | Dart | Mindustry `NetworkIO.writeServerData()` |

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

```json
{
  "id": "stardew",
  "label": "Stardew Valley",
  "type": "static_port",
  "port": 24642
}
```

ET：`game.advertiseOpen` / `game.listOpen`。
