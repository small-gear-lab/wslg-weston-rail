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
  （WSLGd のログに `terminated with signal 11`）。再起動は成功するので放置しているが、原因は未調査。

## 窓が出ない・おかしい

| 症状 | 原因 |
| --- | --- |
| タスクバーのアイコンのタイトルが `[WARN:COPY MODE]` で、窓の中身が無い | FreeRDP が gfxredir 無しでビルドされている。または `use-shared-memory=true` が無い。 |
| `server supports only NLA Security` で msrdc が切断する | 標準 RDP セキュリティ（暗号化なし）を提供していない（パッチ 0004）。 |
| 空のタスクバーアイコンが 2 つ出る | 内容の無い窓を表示している（パッチ 0006、0007）。 |
| 入れ子の KWin が黒いまま、描かれない | 覆われたサーフェスに frame callback が来ない（パッチ 0008）。 |
| 窓の移動やリサイズができず、タイトルバーも無い | msrdc が窓の枠を出さない。CSD の無いクライアント（入れ子のコンポジタなど）は動かせない。 |
| `Detected an unmapped surface or view in the layer list, which should not occur.` | 起動直後のログに出る。実害は確認していない。 |
| `surface width/height doesn't match with buffer` | ビューポートで拡縮されるサーフェス（KWin の 1×1 単色バッファなど）で出る。無害。 |

## 描画の遅れ（1 ストローク遅れて見える）

`Backspace` の押しっぱなしや、IME の未確定表示で、画面が 1 更新分遅れて見えた。IME のロジックは正常で、`preedit_string` は
キーを押した直後に届いていた。調べた結果は次のとおり。

- msrdc の ack は、50〜170 ms 遅れて返る。更新のスキップ条件は、グローバルな
  `currentFrameId − acknowledgedFrameId >= 2`（ログに `frame update is skipped`）。
- present ID は**窓ごとに**増える。kitty は 1 + 6 の 7 窓なので、1 回の描画で何個も消費して、すぐに枠を使い切る。
- kitty（mesa のソフトウェア EGL）は、毎フレーム「全面が更新された」と申告する（`damage_buffer(0,0,INT_MAX,INT_MAX)`）。
  132×94 セルの窓だと約 1189×2069 ピクセル（約 10 MB）を毎回コピーして、msrdc が処理する。窓が大きいほど ack が遅れる。
- スキップした分のダメージは `rail_state->damage` に溜まるだけで、ack が返っても再描画が予約されない。次の commit が来るまで、
  最後の更新が出ない。
- 窓が前面に出るまで、msrdc が ack を返さないことがある（起動直後、約 27 秒間 ack が無かった）。

対策（パッチ 0010）:

1. 新しい内容を一時バッファにコピーして、共有メモリの前回の内容と行ごとに比べ、**変わった範囲だけ**を共有メモリに書き、
   その外接矩形だけを `dirtyRect` にして送る。何も変わらないフレームは、送らない（present ID も消費しない）。
2. スキップしたときにフラグを立て、ack を受けたスレッドからコンポジタのスレッドに再描画を依頼する。

体感を変えたのは 1。2 だけでは、直らなかった。80×24 セルの窓では十分に快適になった。大きい窓の最終的な評価は、これから。

## ランチャーの罠

- `PATH` 上の `kitty` が、`/usr/bin/kitty` をバックグラウンドで起動して即終了するラッパーだと、`dbus-run-session` の親が
  終わって、同じセッションの fcitx5 が `Disconnected from DBus, exiting...` で落ちる。`/usr/bin/kitty` を直接呼ぶ。
- kitty は、`--single-instance` なしでも自分でデーモン化することがある。`dbus-run-session` の下で待ちたいときは
  `--single-instance --wait-for-single-instance-window-close` を使う。
- `GLFW_IM_MODULE=ibus` が環境に残っていると、`text-input-v3` が使われない。

## ビルド

- ビルドスクリプトは、終了コードと成果物のタイムスタンプを確認する。クォートの誤りで、スタブ（`wslgd-notify.so`）が
  黙って更新されなかったことがある。
- zsh では、`'-Dtools=[]'` のように `[]` を含む引数はクォートする。`$G` のように、複数語の変数をコマンドとして展開しない。
