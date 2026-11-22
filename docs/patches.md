# パッチの説明

`patches/mr1667/1667.patch`（3 コミット）を、Weston の `9d841e39` に当て、その上に `patches/local/` を順に当てる
（`scripts/fetch-sources.sh` が `git am` で行う）。

## MR !1667（無改変）

| コミット | 内容 |
| --- | --- |
| Add snapping mechanism: maximize/unmaximize（2 個） | ウィンドウのスナップ（最大化・元に戻す）。 |
| Rebase RDP-RAIL support from microsoft's mirror | WSLg の Weston 9 にある RDP-RAIL（`rdprail-shell`、`rdp-backend` の RAIL 部分）を upstream に載せ替えたもの。 |

MR のパッチは、そのままビルドでき、起動までは行くが、WSLg 上で窓を出すには下の修正が要った。

## 動かすために必要だった修正

| 番号 | 内容 | 症状と原因 |
| --- | --- | --- |
| 0001 | `notify_window_proxy_surface` に compositor を渡す | フォーカスのプロキシをリセットするとき、呼び出し側が `NULL` を渡して NULL 参照で落ちた。 |
| 0002 | `rdp_rail_destroy` でデバッグ用バインディングを破棄しない | `weston_compositor_shutdown` の後で二重解放になり、終了時に落ちた。 |
| 0003 | `WESTON_DISABLE_ABSTRACT_FD` を効くようにする | WSLg は抽象ソケットを使えないため、Xwayland を起動できない。`weston_xwayland_listen` の初期化漏れ、失敗経路での解放、`spawn_xserver` の `-listenfd` など 4 つのバグが連鎖していた。 |
| 0004 | FreeRDP 3 で、暗号化なしの標準 RDP セキュリティを提供する | msrdc が vsock 越しに要求するのは、標準 RDP セキュリティ（暗号化 NONE）だけ。FreeRDP 3 は、この方式でも RSA 2048 の証明書を必要とするので、使い捨ての鍵を組み込んだ（`rdp-local-cert.h`）。 |
| 0005 | RAIL モードでは、出力のレンダーバッファを作らない | 2 枚目のモニタが接続されると、`pixman_renderer_create_renderbuffer: po` のアサーションで落ちた。 |
| 0006、0007 | 内容が無く、一度も表示されていない窓を、隠したままにする | libweston がバッファの無いサーフェスにも寸法を持たせるため、「サイズ 0 → 何か」を表示と解釈して、タスクバーに空のアイコンが 2 つ出た。0006 の `weston_surface_has_content()` 判定は効かず、0007 でバッファの寸法で判定するようにした。 |
| 0008 | RAIL では、覆われたサーフェスにも frame callback を返す | コアは、他の面に全面を覆われたサーフェスの frame callback と presentation feedback を送らない。入れ子の KWin は、黒の 1×1 バッファの親サーフェスを、描画入りのサブサーフェスで全面覆うため、完了通知が来ずに止まり、黒い窓のままだった。出力に `frame_done_when_occluded` を足した。 |
| 0012 | 仮想チャネルのキューを、積まれたらすぐ処理する | **更新が、次の入力イベントまで送り出されない**（最後のキー入力の結果が、次のキーやマウスの動きで初めて出る）。`WTSVirtualChannelWrite()` はキューに積むだけで、送られるのは `WTSVirtualChannelManagerCheckFileDescriptor()` が呼ばれたとき。それをクライアントからの受信時にしか呼んでいなかった。`events[]` にキューの fd 用の枠が残っていたが、FreeRDP 3 で `WTSVirtualChannelManagerGetFileDescriptor` が廃止され、使われていなかった。キューのイベントハンドルを監視するようにした。詳細は [pitfalls.md](pitfalls.md)。 |
| 0013 | 入力メソッドのパネル（`input panel`）をタスクバーに出さない。再表示のとき、ラベルで決めた値を使う | fcitx5 の候補ウィンドウが、出るたびにタスクバーにボタンとして現れた。隠す条件が、親のある窓、ラベルの無い窓、`child window` だけだった。さらに、大きさの無かった窓が大きさを持つ（再表示）とき、`TaskbarButton = 0` を無条件で送っていて、ラベルの判定が繰り返されないため、一度隠す設定にしても、表示のたびにボタンが戻った。 |
| 0014 | RAIL では、入力メソッドのパネルをアニメーションさせない | 日本語入力の候補ウィンドウが、変換のたびに下からスライドインして、規定の位置で何回かバウンドした。`desktop-shell` の `show_input_panel_surface()` が、パネルをバネ（行き過ぎて戻る）で滑り込ませていて、RAIL では、アニメーションの 1 コマごとに、クライアントの本物の窓が動いてしまう。`shell->rdprail_api` があるとき（rdprail-shell）は、アニメーションを走らせない。desktop-shell の挙動は変えない。 |
| 0015 | 入力パネルを、テキストカーソルのあるモニターに収める。位置を聞く前に、メインのサーフェスに解決する | 長い候補ウィンドウが、モニターの下にはみ出したままだった（`calc_input_panel_position()` は、カーソルの右下に置くだけで、出力の範囲を見ていなかった）。カーソルを含む出力を探して、下にはみ出すならカーソルの上側に、横も範囲内に収める。また、キーボードフォーカスがサブサーフェス（クライアント側装飾など）にあるとき、`weston_view_get_pos_offset_global()` が assertion で abort したので、メインのサーフェスで位置を聞くようにした。 |
| 0017 | ウィンドウ移動の要求で、shell surface の無いサーフェスは無視する | トップレベルでない窓（app id の無い 16×16 の窓など）に、msrdc が `WindowMove` を送ると、`shell_backend_request_window_move()` が NULL の `shsurf` を `assert(!shsurf->snapped.is_maximized_requested)` で参照して SIGSEGV になった（fault address `0x141` は、`struct shell_surface` の `snapped.is_maximized_requested` のオフセット）。直前の `if (shsurf && ...)` は NULL を想定していた。MR 由来のコードで、Neovide の窓を動かした直後に踏んだ。`minimize`・`maximize`・`restore`・`snap` と同じく、shell surface が無ければ返る。 |
| 0018 | RDP のクリップボードで、転送中の source から同じ source への 2 回目の要求は、fd を差し替えずに断る | 同じ source への要求が、前の転送が終わる前に来ると、`source->data_source_fd` を新しい fd で上書きしてリトライにしていた。イベントソースは古い fd のままなので、あとで `clipboard_data_source_write()` が `assert(source->data_source_fd == fd)` で abort し、古い fd もリークした。転送中の要求には触らず、2 回目の fd を閉じる（要求した側は EOF を見る。リトライはしない）。 |
| 0019 | 出力を無効にするとき、peer ではなく、`output->buffer` があるかどうかで破棄を決める | `rdp_output_enable()` は、レンダラーの出力状態とレンダーバッファを、RAIL でないときだけ一緒に作る。`rdp_output_disable()` は、`!b->rdp_peer || !HiDefRemoteApp`（RAIL ではない）で破棄を決めていたので、Weston を止めるときにmsrdc が先に切断されていると（`rdp_peer` が NULL）、RAIL で有効にした出力でも、作られていない `output->buffer` を破棄しようとして、`rdp_buffer_destroy(NULL)` の `buffer->output` で SIGSEGV（address 0）になった。`output->buffer` があるときだけ破棄する。 |
| 0020 | RAIL では、ロック画面を出すように `weston-desktop-shell` クライアントに頼まない（`unlock()`） | RAIL の `bind_desktop_shell()` は、`shell->child.desktop_shell` に `weston_rdprail_shell` の resource を入れる。この interface には events が無いのに、`unlock()` が `weston_desktop_shell` の resource だと思って `prepare_lock_surface`（opcode 1）を送り、`wl_resource_post_event()` が`events[1]`（events は NULL）を読んで SIGSEGV（address 0x20）になった。アイドルのタイムアウトでロックされたあと、最初のマウス移動で起きた。RAIL ではクライアントがいないものとして、すぐ `resume_desktop()` する。 |
| 0021 | フェードの surface に、専用の `committed` 関数を使う | `shell_fade_create_view()` のフェードの surface が、全画面ウィンドウの黒背景と同じ `black_surface_committed` を使っていた。`is_black_surface_view()` は、この関数で黒背景を見分けて、`committed_private` を全画面ウィンドウの view として返すが、フェードの surface には`shell`（view ではない）が入っている。フェードの surface は入力を捕まえるので、クリックすると `activate_binding()` が `shell` を view として使い、`weston_surface_to_subsurface(surface=0x1)` で SIGSEGV になった。RAIL では、`desktop_ready` を報告するクライアントがいないので、起動時のフェードの surface が最大 15 秒残る。 |

## 機能と性能

| 番号 | 内容 |
| --- | --- |
| 0009 | `zwp_text_input_manager_v3` を追加する。詳細は [ime.md](ime.md)。 |
| 0010 | gfxredir で、変わった範囲だけを msrdc に送る。ack を受け取った後に、スキップされた更新を再描画する。**0012 の前に、「描画の遅れ」の原因を取り違えて入れたもの**で、0012 のあとにも必要かどうかは、外して比べていない（[pitfalls.md](pitfalls.md)）。 |
| 0011 | カーソルのスプライトやドラッグアイコンの位置合わせで、サブサーフェスのビューが来ても abort しない。 |
| 0016 | `xdg_activation_v1` を追加する。`activate` された窓を、Windows 側のクリックと同じ処理（`shell_backend_request_window_activate()`）で前面に出し、そのあと Z オーダーを msrdc に送る。Wayland のクライアントは、これが無いと自分で別の窓を前面にできない（winit の `Window::focus_window()` が何もしない。Neovide の窓の切り替えが効かなかった）。トークンは、このコンポジタが出したものだけを、1 回、30 秒だけ受け付ける。serial・app_id・surface は検査せず、seat を決めるだけに使う。RDP バックエンドの `notify_window_zorder_change()` は、呼び出し元が無く、Weston の中で起きた Z オーダーの変更が msrdc に届かなかったので、activate のあとに呼ぶ。 |

## 既知の未対応

- MR を Weston 15.0.1 の上に載せ直すと、9 ファイルで衝突する。
- 0004 の鍵の組み込みは、upstream に出す形ではない（設定で切り替えられるようにするべき）。
- 0011 は、原因の根本ではなく、アサーションを避けるだけ。kitty のカーソル用サーフェスが、先に RAIL の窓として扱われる経緯
  （ログに `cursor role is added after creation`）は、調べきれていない。
- 0016 は、`xdg_activation_v1` の global が出ること（`wayland-info`）と、起動してクラッシュしないこと、Neovide の
  `<leader>W` で別の窓へフォーカスが移ることを確認した（Windows 11 + msrdc 1.2.7391、Neovide 0.17.2）。トークンの検証は
  緩い（serial を見ない）。
  `zxdg_decoration_manager_v1` も無いので、winit は Wayland で自前のタイトルバーを描く（フォントは fontconfig の `sans-serif`）。
- 0017 は、実際のビルド設定でのコンパイル確認（`-fsyntax-only`）と、シリーズが `9d841e39` に当たることまでを確認した。再ビルドした Weston で、同じ操作（Neovide の窓を動かす）を試した確認はまだ。
- 0019 は、実際のビルド設定でのコンパイル確認と、シリーズが `9d841e39` に当たることまでを確認した。再ビルドした Weston（`Build: 14.0.0-277-ga3d2a8eb`）を、msrdc が接続された状態で SIGTERM で止めて、WSLgd のログが `exited with status 0` になり、カーネルのログに segfault が出ないことを確認した（0019 の前は、止めるたびに `terminated with signal 11`）。`rdp_rb_discarded_cb()` で、バッファの作り直しに失敗したときは、`output->buffer` が NULL のまま、レンダラーの出力状態だけが残る（止めるときに破棄されない。リークだけで、落ちはしない）。
- 0020 と 0021 は、実際のビルド設定でのコンパイル確認と、シリーズが `9d841e39` に当たることまでを確認した。再ビルドした Weston に入れて動かしている（`Build: 14.0.0-277-ga3d2a8eb`）が、この 2 つの経路を踏む操作（アイドルからの復帰、起動時のフェードの surface へのクリック）は試していない（設定の `idle-time=0` と `startup-animation=none` で、この 2 つの経路はそもそも通らない）。
