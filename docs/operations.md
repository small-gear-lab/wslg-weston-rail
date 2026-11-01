# 運用

`<repo>` はこのリポジトリのパス。システムディストロで root として実行する場合は、`wsl.exe` 経由で、リポジトリを
`/mnt/wslg/distro<repo>` として参照する。

```sh
SYS="wsl.exe --system -d Ubuntu -u root -e sh /mnt/wslg/distro<repo>/scripts"
```

## インストール

1. `scripts/configure.sh` → `fetch-sources.sh` → `build-freerdp.sh` → `build-weston.sh`（[README](../README.md)）。
2. `$SYS/install.sh`: 元の `/usr/bin/weston` を `/usr/libexec/weston-original` に保存し（元の ELF であることを確認する）、
   ラッパーを置く。Weston は再起動しない。
3. `$SYS/restart-weston.sh`: Weston を終了する。WSLGd が `/usr/bin/weston`（ラッパー）を再起動する。**WSLg の GUI の窓は
   すべて閉じる。** `DRYRUN=1` で、止める対象の表示だけ行う。
4. `sudo scripts/install-service.sh`: WSL 起動のたびに、ラッパーの導入と切り替えを自動で行う。

## 切り替わったかの確認

```sh
tail /mnt/wslg/weston-wrapper.log     # "start #1: custom weston, ..." が出ていれば、カスタム版
wayland-info | grep text_input        # zwp_text_input_manager_v3 が見えれば、カスタム版
tail $WORK/ensure.log                 # 起動時の自動適用のログ（$WORK は config.env）
```

ラッパーが 60 秒以内に 3 回起動されると、`fallback to the original weston` と記録して、元の Weston 9 を使う。**Weston を
短時間に何度も再起動しない**こと。

## ビルドして反映する手順

実行中の Weston の足元でライブラリを差し替えると、落ちることがある。次の順で行う。

1. GUI の窓を閉じる。
2. `scripts/build-weston.sh`
3. `$SYS/restart-weston.sh`（前回の起動から 60 秒以上空ける）。

## ロールバック

```sh
$SYS/rollback.sh                       # 保存した元の Weston を /usr/bin/weston に戻す
sudo systemctl disable wslg-weston     # 自動適用をやめる
touch <repo>/DISABLE                   # systemd に触れず、ensure.sh だけを止める
```

システムディストロの変更は WSL の起動で消えるので、完全に戻すだけなら `wsl --shutdown` で再起動し、自動適用を止めておけばよい。
`overlayfs` では、下層のファイルを `rm` しても元には戻らない（コピーで戻す）。

## デバッグ

- ログ: `/mnt/wslg/weston.log`（追記される）、`/mnt/wslg/weston-wrapper.log`、`/mnt/wslg/stderr.log`（落ちたときの
  アサーションやシグナル）、`/mnt/wslg/wlog.log`（FreeRDP）。
- 詳細ログ: Weston を起動する前に `touch <repo>/VERBOSE` すると、`rdp-backend-verbose` のスコープが有効になる。マウス入力や
  フレームの ack なども全部記録されるので、重く、調べ終わったら消す。
- msrdc が起動していないとき: `$SYS/start-msrdc.sh`（WSLGd が 60 秒に 10 回の制限で再起動をあきらめた場合）。
  Windows 側の `msrdc.exe` のうち、`/hvsocketserviceid:00000001-…` が窓用で、`…0002` は別物。触らない。
- 起動が固まったとき（Windows 側から）: `wsl.exe --system -d Ubuntu -u root -e pkill -x xset`。
- Windows 側から msrdc の窓の状態（位置、スタイル、owner）を見るには、PowerShell で `EnumWindows` を使い、msrdc の
  プロセスの窓を列挙する。
- `pgrep -f` / `pkill -f` は、呼び出したシェル自身の引数にもマッチする。`-x` か、`"--socket=wayland-[0]"` のような
  ブラケットの回避を使う。

## テスト

- `test/subsurface-test/`: `./build.sh` で作る。`./subsurface-test 0|1|2` を `WAYLAND_DISPLAY=wayland-0` で動かす。
  モード 0 と 2 は、親サーフェスの frame callback を待って `frame done` と表示する。出ないなら、パッチ 0008 が効いていない。
