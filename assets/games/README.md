# 游戏规则

线上数据源（完整目录）：`https://astral.fan/gamerules.json`  
仓库路径：[`ldoubil/astral.github.io` → `public/gamerules.json`](https://github.com/ldoubil/astral.github.io/blob/main/public/gamerules.json)  
本地 `assets/games/rules.json`：**仅通用回退**（如「其他」），不含具体游戏配置。

## 结构

游戏根级放目录元数据（`id` / `name` / `color` / `icon_asset` / `grid_asset` / …）。  
平台相关配置写在 `platforms.<os>` 下；没有特殊规则可以整段省略。

```json
"platforms": {
  "windows": {
    "lan_game_discover": { "type": "udp_multicast", "multicast": "224.0.2.60:4445", "parser": "minecraft_motd", "title": "{player} · {game}" }
  }
}
```

**仅 Windows** 做发现 / 组播注入 / 127 转发；其它平台只显示房间列表（配置回退 `windows`）。

## 图片字段 `icon_asset` / `grid_asset`

| 写法 | 含义 |
|------|------|
| `https://...` | 网络绝对地址（推荐） |
| `games/...` 或 `/games/...` | 相对 `https://astral.fan/` 解析 |
| `assets/...` | 应用内 asset（本地一般不用） |

## `lan_game_discover`

有这块即启用。对象 = 一条规则；数组 = 多条。

| type | 必填 | 说明 |
|------|------|------|
| `static_port` | `port` | 本机该 UDP 端口在听才宣告 |
| `udp_multicast` | `multicast` `parser` | 听组播再解析 |
| `udp_probe` | `probe` `parser` | 发探测包再解析回复 |

可选：`title`（`{player}` `{game}` `{label}` `{motd}`）、`id`、`label`、`port`（probe 回退端口）。

有 `parser` 且能重建载荷 → 默认本机组播 + 同伴 127 注入/TCP。不必再写 inject/forward 开关。

### Minecraft

```json
{
  "type": "udp_multicast",
  "multicast": "224.0.2.60:4445",
  "parser": "minecraft_motd",
  "title": "{player} · {game}"
}
```

### Mindustry

```json
{
  "type": "udp_probe",
  "probe": "fe01",
  "parser": "mindustry_server",
  "multicast": "227.2.7.7:20151",
  "port": 6567
}
```

`probe: "fe01"` = KryoNet/Arc `DiscoverHost`。

### Stardew Valley

```json
{
  "type": "static_port",
  "port": 24642
}
```

ET：`game.advertiseOpen` / `game.listOpen`。
