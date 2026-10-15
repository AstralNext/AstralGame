# AUR：astral-game-bin

用户侧只需 `yay -S astral-game-bin`。这里只放打包文件，**产物来自 GitHub Release**
（`astral-game-<version>-linux-x64.tar.gz`，由 `.github/workflows/build.yml` 编译）。
包名用 `-bin`：Flutter + Rust 现场编译代价太高，二进制分发是 AUR 上这类应用的常规做法。

## 一次性准备

1. 在 <https://aur.archlinux.org> 注册账号，把 SSH 公钥加到账号设置里。
2. 在 GitHub 仓库加 Secret `AUR_SSH_PRIVATE_KEY`：上面对应的**私钥**全文。

## 发版流程

1. 跑 Build 工作流产出 `astral-game-linux-x64` 产物（推 `v*` 标签或手动触发）。
2. 跑「发布」工作流创建 Release（当前是 draft + prerelease）。
   同一流程里的 `pkg` job 会在 Arch 容器里 `makepkg` 出
   `astral-game-bin-<版本>-1-x86_64.pkg.tar.zst` 并挂到该 Release——**不装 AUR 也能直接
   `sudo pacman -U <附件 URL>` 安装**。
3. 在 GitHub 上把该 Release 点 **Publish** —— 这会触发 `.github/workflows/aur.yml`：
   下载产物算 sha256、bump `pkgver`/`sha256sums`、生成 `.SRCINFO`、推送到 AUR。
   也可以在 Actions 里手动跑「发布 AUR」并填 tag 重推。

所以**不要手改 PKGBUILD 里的 `pkgver` / `sha256sums`**，CI 每次都会覆盖。

## 本地验证

```bash
cp packaging/aur/{PKGBUILD,astral-game-bin.install,fan.astral.next.game.desktop} /tmp/aur-test/
cd /tmp/aur-test
makepkg --printsrcinfo > .SRCINFO   # 校验语法并生成 AUR 需要的元数据
makepkg -f --nodeps                 # 只打包（不装），产出 *.pkg.tar.zst
tar -tf astral-game-bin-*.pkg.tar.zst   # 检查落盘路径
sudo pacman -U astral-game-bin-*.pkg.tar.zst
```

装完可以 `getcap /opt/astral-game/astral_game` 确认能力已打上，并 `astral-game` 启动。

## 包里做了两件不能省的事

- **`.install` 里 setcap**：pacman 不保留 `security.capability` xattr，必须在装完后补
  `cap_net_admin,cap_net_raw+ep`，否则建不了 tun 网卡。
- **`/etc/ld.so.conf.d/astral-game.conf`**：进程带上 file capabilities 后处于
  secure-execution，glibc 会忽略产物自带的 `$ORIGIN/lib` 与 `LD_LIBRARY_PATH`，
  只认 `ld.so.cache`。没有这行，程序启动时连自己的插件 `.so` 都加载不到。

装成包之后，App 里那套「一键授权」就只是兜底了，正常情况不会再弹。
