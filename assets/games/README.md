# 游戏规则

线上数据源（完整目录）：`https://astral.fan/gamerules.json`  
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

| type | 含义 | 典型字段 |
|------|------|----------|
| `static_port` | 固定端口宣告 | `port` |
| `udp_multicast` | 听 UDP 组播再解析 | `multicast` / `multicast_port` / `parser` |

| parser | 游戏 |
|--------|------|
| `minecraft_motd` | MC `[MOTD]…[/MOTD][AD]port[/AD]` |

ET：`game.advertiseOpen` / `game.listOpen`。
