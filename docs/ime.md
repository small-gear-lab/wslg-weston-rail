# 日本語入力（text-input-v3 → input-method-v1 → fcitx5）

## 背景

- kitty（GLFW）は、Wayland で `text-input-v3` だけを話す。
- WSLg の Weston 9 は `text-input-v1` / `input-method-v1` しか出さず、`input_method` を bind できるのは、Weston が
  自分で起動したクライアントだけ（それ以外は `permission to bind input_method denied`）。
- 上流の Weston も `text-input-v3` は持っていない（`text-input-v1` と `input-method-v1` のみ）。

## 実装（パッチ 0009）

`frontend/text-backend.c` に `zwp_text_input_manager_v3` を足した。v3 のクライアントを、**v1 の `input_method_context` の仕組みに
載せる**形にしている。

| v3 クライアント → Weston | Weston → fcitx5（input-method-v1） |
| --- | --- |
| `enable` + `commit` | 内部の `text_input` を activate し、`activate` を送る（既に有効なら `reset`） |
| `set_surrounding_text` | `surrounding_text` |
| `set_content_type` | `content_type`（purpose は v3 の `pin` 以降が 1 つ繰り上がっているので変換） |
| `set_cursor_rectangle` | 入力パネルの位置更新（`update_input_panel_signal`） |
| `commit` | `commit_state(serial)`（serial は `commit` の数） |
| `disable` | deactivate |

| fcitx5（input-method-v1） → Weston → v3 クライアント |
| --- |
| `preedit_string` → `preedit_string(text, cursor, cursor)` + `done`（`preedit_cursor` の値を使う） |
| `commit_string` → `commit_string` + `done` |
| `delete_surrounding_text(index, length)` → `delete_surrounding_text(before, after)` + `done` |
| `keysym`、`preedit_styling`、`cursor_position` 等は v3 に対応が無く、無視する |

- `enter` / `leave` は、キーボードフォーカスに追従する（同じクライアントのサーフェスにフォーカスがあるときだけ）。
- キーの転送（IME が処理しなかったキーをクライアントに戻す）は、v1 の `context.key` / `modifiers` が、デフォルトの
  グラブ経由でフォーカスのあるクライアントにキーを届ける既存の仕組みで足りる。
- `done` の serial は、Weston が受け取った `commit` の数。

## 設定

`config/weston-wslg.ini`:

```ini
[input-method]
allow-any-client=true
path=
```

`allow-any-client=true` で、Weston が起動していないクライアント（Ubuntu 側の fcitx5）も `zwp_input_method_v1` を bind できる。
`path=` は、Weston が `weston-keyboard` を自動起動しないための設定。

## fcitx5 と kitty の起動

- fcitx5: `waylandim` を有効にして、`WAYLAND_DISPLAY` のある環境で起動する。`--disable=wayland,waylandim` は付けない。
  bind に成功すると、起動後の自己診断に `Using Wayland native input method protocol: 1` と出る。
- kitty: `GLFW_IM_MODULE=ibus` が残っていると、`text-input-v3` ではなく ibus（D-Bus）経由になってしまう。外すこと。
  `-o linux_display_server=wayland -o wayland_enable_ime=yes` を付ける。
- `config/kitty-launch` が、これらを行う Windows ショートカット用のランチャー。`wsl.exe -d Ubuntu -- <path>/kitty-launch`
  の形で呼ぶ。X11 版は `config/kitty-launch-x11`。
- `PATH` 上の `kitty` が、バックグラウンド起動して即終了するラッパーの場合は、スクリプトの中で `/usr/bin/kitty` を直接呼ぶ。
  D-Bus セッションの親プロセスが先に終わって、fcitx5 も道連れになる。

## 入れ子の KWin を使う案（採用しなかった）

Weston 15-dev は `wp_single_pixel_buffer_manager_v1` を出すので、KWin（6.6.6）を入れ子で動かせる。KWin は `text-input-v3` を
話し、fcitx5 も KWin が起動できる。実際に動いたが、次の理由で採用しなかった。

- 外側の窓に枠もタイトルバーも無く、移動もリサイズもできない（KWin は CSD を描かず、Weston も `xdg-decoration` を出さない）。
- `background_opacity` が効かず、黒に潰れる（KWin の画面は XRGB）。
- 親サーフェスを描画入りのサブサーフェスが覆う構造のため、窓が 2 枚重なる。

この調査で見つかった frame callback の問題（パッチ 0008）は、入れ子の KWin 以外のクライアントにも関係する。

## 未確認・制限

- 入力パネル（候補ウィンドウ）の位置は、`rdprail-shell` 上での厳密な確認をしていない。
- `text-input-v3` の `set_text_change_cause` は無視している。
- GTK4 や Qt6 のクライアントは試していない。
- Xwayland のアプリは、これまでどおり XIM / fcitx のモジュールを使う。
