# はまりどころと調査の記録

## 初回起動のデッドロック（WSLGd の `xset`）

WSLGd は、FontMonitor が `xset +fp …` を Xwayland に対して**同期的に**実行する。Xwayland が死んでいる間にこれを実行すると
応答がなく、WSLGd のメインループが `wait4` で止まる。Weston はゾンビのまま再起動されず、GUI が一切出なくなる。

最初の自動適用は、WSLGd が起動した 3 秒後に Weston を落としたため、ちょうどこれに当たった。`ensure.sh` は次の 2 つで避ける。

- WSLGd が落ち着く（自身の msrdc が繋がり、`xset` が動いておらず、さらに 5 秒）まで待ってから切り替える。
- カスタム版が上がらないまま、WSLGd の子の `xset` が 8 秒以上固まっていれば、それを終了させる。

手動での復旧は、`wsl.exe --system -d Ubuntu -u root -e pkill -x xset`。

## 再起動の回数制限

- WSLGd は、子が 60 秒間に 10 回を超えて終了すると、再起動をあきらめる。msrdc がこれに当たったら、`start-msrdc.sh`。
- ラッパーは、60 秒以内の 3 回目の起動から元の Weston にフォールバックする。開発中に再起動を重ねると、これに当たる。
  次の再起動は、前回から 60 秒以上空ける。

## ライブラリの差し替えと終了時の SEGV

- `ninja install` で、実行中の Weston のライブラリを差し替えると落ちたことがある（WSLGd が再起動する）。ビルドの反映は、
  Weston を再起動する前提で行う。
- アクティブなセッションがあるカスタム版を SIGTERM で止めると、`rdp-backend.so` 内で SIGSEGV になることがある
  （WSLGd のログに `terminated with signal 11`、カーネルのログに `segfault at 0 ... in rdp-backend.so`）。再起動は成功する。原因は、msrdc が先に切断されて `rdp_peer` が NULL になっていると、`rdp_output_disable()` が「RAIL ではない」と判断して、RAIL では作られていない `output->buffer`（NULL）を `rdp_buffer_destroy()` に渡していたこと（パッチ 0019）。

## 窓が出ない・おかしい

| 症状 | 原因 |
| --- | --- |
| タスクバーのアイコンのタイトルが `[WARN:COPY MODE]` で、窓の中身が無い | FreeRDP が gfxredir 無しでビルドされている。または `use-shared-memory=true` が無い。 |
| `server supports only NLA Security` で msrdc が切断する | 標準 RDP セキュリティ（暗号化なし）を提供していない（パッチ 0004）。 |
| 空のタスクバーアイコンが 2 つ出る | 内容の無い窓を表示している（パッチ 0006、0007）。 |
| 長い候補ウィンドウが、モニターの下にはみ出したままになる | 入力パネルの位置が、モニターの範囲を見ていなかった（パッチ 0015）。 |
| 候補ウィンドウを出したら Weston が落ちて、そのあと IME がオンにならない | サブサーフェスのビューで位置を聞いて abort（パッチ 0015）。60 秒以内に 3 回起動すると、ラッパーが標準の Weston 9 に切り替えるので、`text-input-v3` が無くなって IME が効かなくなる（`/mnt/wslg/weston-wrapper.log` に `fallback to the original weston`）。 |
| 候補ウィンドウが、出るたびに下からスライドインして、バウンドする | `desktop-shell` の入力パネルのアニメーション。RAIL では 1 コマごとに窓が動く（パッチ 0014）。 |
| 日本語入力の候補ウィンドウが、出るたびにタスクバーに現れる | `input panel` のラベルの窓が、タスクバーの対象になっていた。再表示のたびにボタンが戻っていた（パッチ 0013）。 |
| WSL の起動後、Windows 側から `kitty-launch` を 1 回目に呼ぶと窓が消えて、2 回目で立ち上がる | WSL の起動直後は、WSLg 標準の Weston 9 が動いていて、`ensure.sh` が数秒後にカスタム版へ差し替える（`restart-weston.sh`）。その前に立ち上がった kitty は、標準の Weston ごと落ちる。`config/kitty-launch` は、`/mnt/wslg/weston-wrapper.log` の最後の `start`・`fallback` の行で、差し替えが済むまで最大 60 秒待つ（自動適用が無効なら待たない）。Ubuntu 側からは、システムディストロの Weston のプロセスが見えないので、プロセスではなくログで見ている。 |
| `desktop-shell.so` で SIGSEGV（`shell_backend_request_window_move`）。Neovide の窓を動かすと、GUI ごと落ちる | msrdc がトップレベルでない窓（app id の無い 16×16 の窓など）に `WindowMove` を送ると、shell surface の無いサーフェスで `assert(!shsurf->snapped.is_maximized_requested)` が NULL を参照した（パッチ 0017）。 |
| 起動して 15 秒以内に窓をクリックすると、Weston が落ちる（`activate_binding`、`weston_surface_to_subsurface (surface=0x1)`） | 起動時のフェードの黒いカーテンが、全モニターを覆って入力を捕まえている（`desktop_ready` が来ないので、15 秒のタイマーまで残る）。フェードのカーテンは、全画面ウィンドウの黒背景と同じ `black_surface_committed` を使うので、`is_black_surface_view()` が取り違えて、その `committed_private`（`desktop_shell`）を view として使う。コードはパッチ 0021（フェードの surface 専用の `committed` 関数）で直した。さらに `[shell] startup-animation=none` で、カーテンを作らない（`config/weston-wslg.ini`）。 |
| 300 秒ほど操作せず、マウスを動かした瞬間に Weston が落ちる（`unlock` → `weston_desktop_shell_send_prepare_lock_surface`） | アイドルのタイムアウトで、desktop-shell が黒いカーテンを出してロックする。復帰のマウス移動で `unlock()` が走り、`shell->child.desktop_shell` に `prepare_lock_surface` を送る。RAIL では、これは `weston_rdprail_shell` の resource で events が無いので、`wl_resource_post_event()` が落ちる。コードはパッチ 0020 で直した。さらに `[core] idle-time=0` で、アイドルのタイムアウトを切る（`config/weston-wslg.ini`）。 |
| 入れ子の KWin が黒いまま、描かれない | 覆われたサーフェスに frame callback が来ない（パッチ 0008）。 |
| 窓の移動やリサイズができず、タイトルバーも無い | msrdc が窓の枠を出さない。CSD の無いクライアント（入れ子のコンポジタなど）は動かせない。 |
| `Detected an unmapped surface or view in the layer list, which should not occur.` | 起動直後のログに出る。実害は確認していない。 |
| `surface width/height doesn't match with buffer` | ビューポートで拡縮されるサーフェス（KWin の 1×1 単色バッファなど）で出る。無害。 |

## 最後の更新が、次の入力まで出ない（仮想チャネルのキュー）

**症状**: 最後のキー入力の結果が、次のキーを押すか、マウスを動かすか、Alt を押すまで描画されない（`ll` + Enter の結果が出ない、
`Backspace` が 1 つ遅れる、など）。IME の有無、窓の大きさ、半透明、モニターには関係がなかった。Ctrl+L の
ように、すぐ出るものもあった（推測: 入力の直後に別の受信が続くため）。

**原因**: gfxredir の `PresentBuffer` や窓の命令は、`WTSVirtualChannelWrite()` で、FreeRDP の仮想チャネルのキュー
（`vcm->queue`）に**積まれるだけ**。実際に送られるのは、`WTSVirtualChannelManagerCheckFileDescriptor()` が呼ばれたときで、
Weston はそれを、クライアントからの受信（`rdp_client_activity`）と、いくつかの待ちループでしか呼んでいなかった。
そのため、更新を積んでも、クライアントから何か届くまで送り出されず、最後の更新は次の入力まで待たされた。
ack が「遅れて」戻っていたのも、更新がまだ送られていなかったから。`events[]` に、キューの fd 用の枠
（`+1 for WTSVirtualChannelManagerGetFileDescriptor`）が残っていたが、FreeRDP 3 でその関数が廃止されて、移植のときに使われなくなっていた。

**対策（パッチ 0012）**: `WTSVirtualChannelManagerGetEventHandle()` のハンドルを、Weston のイベントループで監視して、
キューに積まれたらすぐ `WTSVirtualChannelManagerCheckFileDescriptor()` を呼ぶ。

**取り違えた経緯**（[history.md](history.md)）: 最初、窓の更新量や ack の遅れが原因だと考えて、0010（差分だけを送る）を入れた。
窓が小さいと改善して見えたのは、更新の間隔が詰まって、クライアントから何かが届く機会が増えたためかもしれない（推測）。後には、「msrdc（Windows 側）が、入力まで
描画を寝かせている」と結論しかけて、Weston から窓の命令やダミーの present を送って起こそうとしたが、効かなかった。
**WSLg 標準の Weston（FreeRDP 2 系）で、X11 の kitty が症状なく動く**ことを確かめて、はじめて自分たちの側の問題だと分かった。
標準の Weston との比較（A/B）を、もっと早くやるべきだった。

調べるときの目印:

- 症状が出ている間、ログ（`ACK  present:...` の行など）で、更新は「送った」ことになっているのに、ack が入力のタイミングまで戻らない。
- ack が戻らないまま Weston を再起動すると、窓の破棄で「update is still pending in client side」を、窓ごとに 10 秒待つので、
  終了に 1〜5 分かかる。0012 のあとは、この待ちがほぼ無くなる。

**0010 について**: 0010 の差分送信は、この問題の原因ではなかった。0012 のあとにも必要かどうかは、外して比べていない。
更新量が多い窓で効く可能性はあるので、残してある。

### 試して、効かなかったもの（参考）

| 試したこと | 結果 |
| --- | --- |
| スキップを最大 100 ms にして、強制的に送る | 変わらない（送るものが無かった） |
| `DrainOutputBuffer` | 変わらない（これはトランスポートの送信バッファで、チャネルのキューは別） |
| 同じ範囲、1x1 の present の再送 | 変わらない |
| 窓の位置の再送 | 変わらない |
| 窓の位置と大きさの再送 | **悪化**（再レイアウトが走る） |
| 本体の窓に、100 ms ごとのダミーの present（心拍） | 変わらない |
| Windows の入力方式を、Google 日本語入力から変える | 変わらない |

## ランチャーの罠

- **X11 版（`kitty-launch-x11`）は、fcitx5 が動いていないと、`--disable=wayland,waylandim` つきで起動する**。Weston を再起動すると、元の
  fcitx5 は Wayland の接続を失って終了する。そのあとに X11 版を使うと、Wayland に繋がらない fcitx5 が残り、Wayland 版の kitty で
  IME がオンにならない（`fcitx5 --replace` を前景で動かすと、`permission to bind input_method denied` や、Wayland の接続エラーが見える）。
  Wayland 版（`kitty-launch`）は、そういう fcitx5 を見つけたら入れ替える。

- `PATH` 上の `kitty` が、`/usr/bin/kitty` をバックグラウンドで起動して即終了するラッパーだと、`dbus-run-session` の親が
  終わって、同じセッションの fcitx5 が `Disconnected from DBus, exiting...` で落ちる。`/usr/bin/kitty` を直接呼ぶ。
- kitty は、`--single-instance` なしでも自分でデーモン化することがある。`dbus-run-session` の下で待ちたいときは
  `--single-instance --wait-for-single-instance-window-close` を使う。
- `GLFW_IM_MODULE=ibus` が環境に残っていると、`text-input-v3` が使われない。

## ビルド

- meson は、見つけた依存をキャッシュする。`apt-get remove --autoremove` で `xwayland`（`xwayland.pc`）が消えたあと、
  ソースを触って `ninja` を走らせると、再生成が `xwayland` の pkg-config 変数で失敗した（`xwayland` を入れ直して直った）。
- `build-weston.sh` の最後は `ninja install` で、動いている Weston のファイルを上書きする。ビルドだけ確かめたいときは
  `ninja -C <build>` だけを走らせる。インストールされた `.so` は、rpath が書き換わるので、ビルドとはバイト列が一致しない。
- ビルドスクリプトは、終了コードと成果物のタイムスタンプを確認する。クォートの誤りで、スタブ（`wslgd-notify.so`）が
  黙って更新されなかったことがある。
- zsh では、`'-Dtools=[]'` のように `[]` を含む引数はクォートする。`$G` のように、複数語の変数をコマンドとして展開しない。
