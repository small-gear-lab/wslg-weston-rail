# wslg-weston-rail

WSLg の Weston を、upstream ベースの Weston（RDP-RAIL パッチ入り）に差し替える実験の記録とレシピ。

> **注意: 実験段階の記録であり、保証はない。**
>
> - 作者の 1 つの環境（下の「状態」）でしか確認していない。
> - **この手順を最初から通しで試したわけではない。** 確認したのは、パッチシリーズが指定のコミットにきれいに当たること、
>   その木から Weston がビルドできること、スクリプトの文法までで、`install.sh` 以降（システムディストロへの導入、自動適用）は、
>   このリポジトリの手順では再実行していない。動いている環境は、同じ内容の元のスクリプトで作った。
> - WSLg のシステムディストロの `/usr/bin/weston` を差し替える。誤ると、WSLg の GUI が起動しなくなることがある
>   （元の Weston への自動フォールバックと、[ロールバック手順](docs/operations.md)はある）。
> - **設計図から作ったものではなく、動かして観察し、仮説を立てて直すことを繰り返した最終状態の記録。** 理由を全部理解した上で動いて
>   いるわけではなく、「確認できた範囲では、たまたま動いている」可能性が高い。経緯と、当てになっていない点は
>   [docs/history.md](docs/history.md) に書いた。
> - 自己責任で、先に [docs/operations.md](docs/operations.md) と [docs/pitfalls.md](docs/pitfalls.md) を読むこと。

目的は、WSLg 上で **kitty や fcitx5 を Wayland ネイティブで動かし、日本語入力まで通す**こと。
WSLg 同梱の Weston 9 は `text-input-v1` しか話せず、`input_method` も Weston 自身が起動したクライアントにしか
bind させない。kitty（GLFW）が使う `text-input-v3` は使えず、fcitx5 も外から繋げなかった。

結果として、次の構成で動いている。

```
kitty (Wayland, text-input-v3)
   │
独自 Weston 15-dev (RDP backend + RAIL shell + text-input-v3 対応)   ← WSLg のシステムディストロ内で動く
   │  zwp_input_method_v1                       │  RDP / RAIL / gfxredir
fcitx5 (Ubuntu 側、waylandim)                    msrdc.exe (Windows)
```

## 状態

- 動作確認した環境: Windows 11 + WSL2（カーネル 6.18.58.1）、Ubuntu 26.04、WSLg のシステムディストロは Azure Linux 3.0
  （Weston 9.0.0、glibc 2.38）、FreeRDP 3.32.1、kitty 0.49.2 + fcitx5。
- 実験段階。WSLg のシステムディストロの `/usr/bin/weston` を差し替える。壊れた場合に備えて、元の Weston へ自動で
  フォールバックする仕組みと、ロールバック手順がある（[docs/operations.md](docs/operations.md)）。
- ベースにしている Weston のコミットは `9d841e39`（14.0.91+579）。MR !1667 は止まっていて、最新の 15.0.1 には 9 ファイルで
  衝突する。**パッチはこのコミットにしか素直に当たらない。**

## 構成

| パス | 内容 |
| --- | --- |
| `patches/mr1667/1667.patch` | Weston の MR !1667（RDP-RAIL の upstream への移植、gpotter2 作）。**無改変**。 |
| `patches/local/*.patch` | MR の上に重ねた 13 個の修正と機能（[docs/patches.md](docs/patches.md)）。 |
| `scripts/` | 設定・ソース取得・ビルド・インストール・ロールバック・起動時の自動適用。 |
| `wrap/` | システムディストロ内で、Ubuntu 側でビルドした Weston を Ubuntu のローダ経由で動かす。 |
| `src/wslgd-notify.c` | WSLGd が待つ MS 製モジュール `wslgd-notify.so` の代用品。 |
| `systemd/` | WSL 起動のたびに適用し直す systemd unit のテンプレート。 |
| `config/` | `weston-wslg.ini`、kitty のランチャー（Wayland 版と X11 版）。 |
| `test/subsurface-test/` | サブサーフェスと frame callback の挙動を確かめるテストクライアント。 |
| `docs/` | [経緯](docs/history.md)、[仕組み](docs/architecture.md)、[パッチ](docs/patches.md)、[IME](docs/ime.md)、[運用](docs/operations.md)、[はまりどころ](docs/pitfalls.md)。 |

## 手順の概要

Ubuntu 側で、ユーザーとして実行する（`<repo>` はこのリポジトリ）。

```sh
<repo>/scripts/configure.sh          # config.env を作る（置き場所の設定）
<repo>/scripts/fetch-sources.sh      # Weston（MR とパッチを適用）と FreeRDP のソースを取得
<repo>/scripts/build-freerdp.sh      # gfxredir を有効にした FreeRDP をビルド
<repo>/scripts/build-weston.sh       # Weston をビルドしてインストール
```

WSLg のシステムディストロに差し込む（Windows 側の PowerShell、または Ubuntu から `wsl.exe` 経由）。

```sh
wsl.exe --system -d Ubuntu -u root -e sh /mnt/wslg/distro<repo>/scripts/install.sh   # ラッパーを入れる（再起動はしない）
wsl.exe --system -d Ubuntu -u root -e sh /mnt/wslg/distro<repo>/scripts/restart-weston.sh   # Weston を再起動（GUI の窓は全部閉じる）
sudo <repo>/scripts/install-service.sh                                               # WSL 起動のたびに自動で適用する
```

日本語入力が要るなら、`[input-method] allow-any-client=true` を `config/weston-wslg.ini` で有効にした上で（標準で有効）、
fcitx5 を `waylandim` 有効で起動し、kitty は `GLFW_IM_MODULE` を外して Wayland で起動する
（[docs/ime.md](docs/ime.md)、`config/kitty-launch`）。

ビルドの依存パッケージ（Ubuntu 26.04 で、実際に入れたもの）:

```sh
sudo apt-get install -y --no-install-recommends meson ninja-build pkgconf wayland-protocols libwayland-dev \
  libxkbcommon-dev libpixman-1-dev libcairo2-dev libpng-dev libjpeg-dev libinput-dev libdrm-dev libgbm-dev \
  libegl-dev libgles-dev libudev-dev libevdev-dev libdisplay-info-dev libseat-dev libxcb1-dev \
  libxcb-composite0-dev libxcb-xfixes0-dev libxcb-cursor-dev libxcb-image0-dev libxcb-render-util0-dev \
  libxcursor-dev freerdp3-dev libwinpr3-dev librsvg2-dev libglib2.0-dev libpam0g-dev libsystemd-dev \
  liblcms2-dev libmtdev-dev libpango1.0-dev libfreetype-dev libfontconfig-dev
```

これに加えて、`build-essential`、`git`、`cmake`（FreeRDP のビルド）、`libwayland-bin`（`wayland-scanner`、テストクライアント用）が
要る。作者の環境では、これらは別の機会に入っていたので、上のコマンドには含まれていない。FreeRDP のソースを取るために、
apt の `deb-src` も有効にしておく。**クリーンな環境での確認はしていない**ので、足りないものは `meson setup` / `cmake` の
エラーに従って足すこと。

## ライセンスと出典

このリポジトリのスクリプト、文書、設定、テストクライアント、`src/` は、[MIT](LICENSE-MIT) または
[Apache-2.0](LICENSE-APACHE) のどちらかを選んで利用できる。特に明記しない限り、このプロジェクトに投稿されたものも、
追加の条件なしに同じ条件で提供される。

`patches/` は、この選択の**対象外**:

- `patches/mr1667/1667.patch` は、Weston の MR !1667（gpotter2 ほか、RDP-RAIL の部分は Microsoft の WSLg フォーク由来）。
  **無改変**で、元の作者の著作権と、Weston のファイルのライセンス（MIT）に従う。
  出典: https://gitlab.freedesktop.org/wayland/weston/-/merge_requests/1667
- `patches/local/` は、Weston のファイルへの変更で、そのファイルのライセンス（Weston の MIT）に従う。そのまま upstream に
  出せるようにするため。詳細は [patches/README.md](patches/README.md)。

使っている第三者のソフトウェアは [NOTICE](NOTICE) を参照。

なお、`rdp-backend` に組み込んだ RSA 2048 の鍵と証明書（パッチ 0004）は、公開されている使い捨てのもの。暗号化なしの
ローカル接続（vsock）で、FreeRDP 3 が証明書を要求するために置いてある。秘密ではなく、通信の保護にも使っていない。
