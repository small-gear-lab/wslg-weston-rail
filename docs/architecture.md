# 仕組み

## WSLg の構造

- WSLg は、ユーザーのディストロとは別の「システムディストロ」（Azure Linux 3.0、glibc 2.38）の中で動く。読み取り専用の
  イメージの上に overlayfs が載っていて、**変更は WSL を起動するたびに失われる**。
- `WSLGd` がシステムディストロで次を起動する。
  - Weston: `/usr/bin/weston --backend=rdp-backend.so --modules=wslgd-notify.so --xwayland --socket=wayland-0
    --shell=rdprail-shell.so --log=/mnt/wslg/weston.log --logger-scopes=log,rdp-backend,rdprail-shell`
  - 準備完了の通知を待つ（`$WSLGD_NOTIFY_SOCKET`、`wslgd-notify.so` が接続する）。
  - Windows 側の `msrdc.exe`（RDP クライアント）。vsock（hvsocket）で Weston に繋ぐ。
  - Weston に渡す待ち受けソケットは、fd 番号を環境変数 `USE_VSOCK` で渡す。
- Weston は WSLg 同梱の **Weston 9.0.0（MS のフォーク）**。RDP バックエンドと `rdprail-shell` で、Linux の窓を
  Windows の窓（RAIL）として出す。
- ユーザーのディストロのルートは、システムディストロから `/mnt/wslg/distro` で読み取り専用に見える。
- WSLGd は、子プロセスが 60 秒間に 10 回を超えて終了すると、再起動をあきらめる。FontMonitor が `xset +fp` を
  **同期的に**実行するため、これが固まると WSLGd 全体が止まる（[pitfalls.md](pitfalls.md)）。

## msrdc が要求すること

- 標準 RDP セキュリティで、暗号化なし（パッチ 0004）。
- GCC のクライアントデータブロック `0xC00C`、`0xC00D` のエラーは致命的ではない。
- 描画は **gfxredir**（共有メモリを使うグラフィックスのリダイレクト、ケイパビリティ 0x2000）。これが無いと「COPY MODE」に
  なり、タスクバーのアイコンのタイトルが `[WARN:COPY MODE]` になって、窓の中身が出ない。Ubuntu の FreeRDP は
  gfxredir チャネルを既定で無効にしてビルドしている（`channels/gfxredir/ChannelOptions.cmake` の `OPTION_DEFAULT OFF`）ので、
  `-DCHANNEL_GFXREDIR=ON` で自前ビルドする（`scripts/build-freerdp.sh`）。
- Weston 側で `[rdprail] use-shared-memory=true`（`config/weston-wslg.ini`）。
- モニタが 2 つ見える場合がある。
- msrdc は、窓のスタイルを固定で上書きする。キャプションも枠も無い窓（スタイル `0x96070000`）になるので、
  **移動とリサイズは、クライアント側装飾（CSD）が出す要求でしか行えない**。

## 差し替えの方式

システムディストロの `/usr/bin/weston` を、ラッパー（`scripts/weston-wrapper`）に置き換える。WSLGd は今までどおりそれを
起動する。

1. ラッパーは、Ubuntu 側（ユーザーのディストロ）でビルドした Weston を、**Ubuntu のローダ**
   （`/mnt/wslg/distro/lib64/ld-linux-x86-64.so.2 --library-path …`）で動かす（`wrap/run-ubuntu`）。システムディストロの
   glibc が古いので、Ubuntu のライブラリ一式で動かす必要がある。
2. WSLGd が `USE_VSOCK=<fd>` で渡すソケットを、`--external-listener-fd=<fd>` に変換する。
3. `WESTON_MODULE_MAP`、`WESTON_DATA_DIR`、`XKB_CONFIG_ROOT` を設定し、`--config=config/weston-wslg.ini` を足す。
4. 古い Xwayland のロックとソケットが残っていれば消す。
5. **フォールバック**: 60 秒以内の 3 回目の起動からは、元の Weston（`/usr/libexec/weston-original`）を使う。Ubuntu 側が
   見えない場合も同じ。
6. `wslgd-notify.so` は、MS 製の代用品（`src/wslgd-notify.c`）。通知ソケットに接続して閉じるだけで、接続できなくても成功を返す。

システムディストロの変更は起動のたびに失われるので、`wslg-weston.service`（Ubuntu 側の systemd）が `scripts/ensure.sh` を
実行して、毎回適用し直す。

## 起動時の自動適用（ensure.sh）

root で動く。

1. 使える `wsl.exe` の interop ソケットを探す（サービスには `WSL_INTEROP` も Windows の PATH も無い）。
2. WSLGd と最初の Weston が上がるのを待つ。
3. ラッパーが入っていなければ `install.sh` を実行する。
4. **WSLGd が落ち着くのを待つ**: WSLGd 自身の msrdc が繋がるまで（最大 120 秒）、`xset` が動いていない状態になるまで、
   さらに 5 秒。その後、Weston を 1 回だけ再起動して、カスタム版に切り替える。
5. カスタム版が上がるまで確認する。`xset` が WSLGd の子として 8 秒以上固まっていれば、それを終了させる。
6. 最後まで msrdc が現れなければ、`start-msrdc.sh` で手動起動する。

止めたいときは、リポジトリ直下に `DISABLE` というファイルを作る（systemd には触れずに済む）。

## 描画経路（gfxredir）

Weston は、サーフェスごとに RAIL の窓を作る。**サブサーフェスも、owner 付きの別の RAIL 窓**として出る
（タイトルは `sub-surface (Linux)`）。kitty は、本体 1 + タイトルバーと影のサブサーフェス 6 の 7 窓になる。

内容は共有メモリのバッファにコピーされ、`PresentBuffer` で msrdc に渡される。msrdc は表示すると、窓ごとの
`present_buffer_ack` を返す。

更新のスキップ条件は、グローバルな `currentFrameId − acknowledgedFrameId >= 2`。present ID は窓ごとに増えるので、
窓の多いクライアントでは、すぐに枠を使い切る。性能の詳細は [pitfalls.md](pitfalls.md)。
