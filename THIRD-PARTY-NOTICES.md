# 第三方组件与许可声明

本文件列出 Astral Game 发行产物中包含或链接的第三方组件，以及各自的上游来源与许可证。
Astral Game 自身的许可证见 [LICENSE](LICENSE)。

> 说明：本文件只记录**许可证名称与来源**，不转载许可全文；完整条款请访问对应上游链接。
> 标注「待确认」的条目表示我们尚未核实该二进制的分发条款，需要在正式分发前补齐，**不要**据此认为已合规。

## 一、随 Windows 发行版分发的二进制

| 组件 | 版本 | 许可证 | 来源 | 状态 |
| --- | --- | --- | --- | --- |
| `wintun.dll` | 0.14.1（Wintun Driver） | 待确认（上游 Wintun 项目许可证） | <https://www.wintun.net/> | 待确认 |
| `Packet.dll` | 1.79（Npcap） | Npcap License（专有条款，允许随第三方软件分发的条件需核对） | <https://npcap.com/> | 待确认 |
| `steam_api64.dll` | 10.51.08.25（Steam Client API） | Steamworks SDK License（Valve，专有；随 SDK 附带的分发条款） | <https://partner.steamgames.com/doc/sdk> | 待确认 |
| `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll` | Microsoft Visual C++ 2015-2022 Redistributable | Microsoft 可再分发组件条款 | <https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist> | 按微软条款分发 |
| `tools/smartdns/smartdns.exe` | 上游未在二进制内标注版本 | GPL-3.0（依据上游仓库声明） | <https://github.com/pymumu/smartdns> | 待确认：GPL-3.0 二进制分发需同时提供对应源码获取方式 |

其中 `wintun.dll`、`Packet.dll`、`steam_api64.dll` 与 MSVC 运行库由 `windows/CMakeLists.txt` 从 `dlls/` 安装到可执行文件同目录；`smartdns.exe` 与 `tools/smartdns/smartdns.conf` 安装到 `native/dns/smartdns/`。

## 二、链接进 Rust 核心库（`rust/`）

| 组件 | 版本 / 分支 | 许可证 | 来源 |
| --- | --- | --- | --- |
| EasyTier | 修改分支 `main-astral` | LGPL-3.0 | 上游 <https://github.com/EasyTier/EasyTier>，本项目的修改分支 <https://github.com/ldoubil/EasyTier/tree/main-astral> |
| steamworks（Rust 绑定，含本地补丁） | 0.13.1，`rust/vendor/steamworks` | MIT OR Apache-2.0 | <https://github.com/Noxime/steamworks-rs> |
| wintun（Rust 绑定） | 0.5.1 | MIT | <https://github.com/nulldotblack/wintun> |
| flutter_rust_bridge | 2.12.0 | MIT | <https://github.com/fzyzcjy/flutter_rust_bridge> |
| 其余 crates.io / git 依赖 | 见 `rust/Cargo.lock` | 绝大多数为 MIT / Apache-2.0（个别为 BSD-3-Clause、ISC、MPL-2.0 等） | 见 `rust/Cargo.lock` 中各包的 `source` 与仓库内 `Cargo.lock` 元数据 |

EasyTier 以 LGPL-3.0 发布并通过 Rust 依赖静态链接进本项目的核心库。依据 LGPL-3.0，本项目已公开其修改分支 `main-astral` 的源码；如需替换该部分，可基于该分支重新编译。

## 三、Flutter / Dart 依赖

Dart 侧依赖全部为源码依赖，完整清单见 `pubspec.lock`，各包许可证文本随包分发（位于 pub cache 中各包的 `LICENSE` 文件）。主要依赖的许可证类型：

| 组件 | 许可证 | 来源 |
| --- | --- | --- |
| Flutter SDK 与 `flutter_localizations`、`flutter_test` | BSD-3-Clause | <https://github.com/flutter/flutter> |
| `intl` | BSD-3-Clause | <https://github.com/dart-lang/i18n> |
| `isar_community`、`isar_community_flutter_libs` | Apache-2.0 | <https://github.com/isar-community/isar> |
| `flutter_rust_bridge`（Dart 侧） | MIT | <https://github.com/fzyzcjy/flutter_rust_bridge> |
| 其他 `pubspec.yaml` 中列出的插件与工具包 | 以各包 `LICENSE` 为准（多为 BSD-3-Clause / MIT / Apache-2.0） | <https://pub.dev/packages> |

## 四、仅构建期使用、不随产物分发

| 工具 | 许可证 | 来源 |
| --- | --- | --- |
| Flutter / Dart SDK | BSD-3-Clause | <https://github.com/flutter/flutter> |
| Rust 工具链（rustc / cargo / rustfmt / clippy） | MIT OR Apache-2.0 | <https://github.com/rust-lang/rust> |
| protoc（Protocol Buffers 编译器） | BSD-3-Clause | <https://github.com/protocolbuffers/protobuf> |
| NASM | BSD-2-Clause | <https://www.nasm.us/> |
| Inno Setup 6（制作 Windows 安装包） | Inno Setup License | <https://jrsoftware.org/isinfo.php> |
| Android NDK / SDK（构建 Android 包） | Android SDK 条款 / Apache-2.0 等 | <https://developer.android.com/> |

## 五、待确认事项

以下条目需要在正式分发前补齐核实，当前不做结论：

1. `wintun.dll` 0.14.1 的具体分发条款（上游允许以二进制形式随第三方软件分发的条件）。
2. `Packet.dll`（Npcap 1.79）以 Npcap 免费版/商业版分发时的授权条件。
3. `steam_api64.dll` 随本项目分发的合规性（Steamworks SDK 对分发形式与关联 AppID 的要求）。
4. `smartdns.exe` 的 GPL-3.0 合规方式（随产物提供对应源码或书面源码获取途径）。
