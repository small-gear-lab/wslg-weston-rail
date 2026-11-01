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

## 機能と性能

| 番号 | 内容 |
| --- | --- |
| 0009 | `zwp_text_input_manager_v3` を追加する。詳細は [ime.md](ime.md)。 |
| 0010 | gfxredir で、変わった範囲だけを msrdc に送る。ack を受け取った後に、スキップされた更新を再描画する。**0012 の前に、「描画の遅れ」の原因を取り違えて入れたもの**で、0012 のあとにも必要かどうかは、外して比べていない（[pitfalls.md](pitfalls.md)）。 |
| 0011 | カーソルのスプライトやドラッグアイコンの位置合わせで、サブサーフェスのビューが来ても abort しない。 |

## 既知の未対応

- MR を Weston 15.0.1 の上に載せ直すと、9 ファイルで衝突する。
- 0004 の鍵の組み込みは、upstream に出す形ではない（設定で切り替えられるようにするべき）。
- 0011 は、原因の根本ではなく、アサーションを避けるだけ。kitty のカーソル用サーフェスが、先に RAIL の窓として扱われる経緯
  （ログに `cursor role is added after creation`）は、調べきれていない。
