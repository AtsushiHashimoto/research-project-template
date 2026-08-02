# Issue #121 仕様: quality-check.sh の実効化

- 状態: approved（auto-reviewer 判断済み。条件を下記に反映。ログ: 121-auto-decisions.md）
- 由来: Integrity Review #114 H8

## 背景

quality-check は `/commit-merge` `/task-run` `/issue-finish` の**完了ゲート**だが、
実効的にほぼ無検査のまま「All quality checks passed」と表示していた。

- shellcheck が devcontainer に未導入で**無言スキップ**
- `mapfile` は bash 4+ 専用。macOS（bash 3.2）＋shellcheck 有の環境では
  `mapfile: command not found` → `SH_FILES: unbound variable` となり、
  **shellcheck を黙って飛ばしたまま `All quality checks passed` / exit 0 になる**
  （検証で判明。当初「異常終了」と書いていたが、実態は緑で通る silent-wrong だった）
- `scripts/qa/*.py`（11ファイル）と `claude-san` はそもそも検査対象外
- CI も無い

なお #117/#118/#119 で再発防止検査3種（スキル参照名の実在 / ラベル定義と説明文 /
スキル一覧の差分）が既に入っており、それらは本 issue の対象外。

## 設計

### D1: bash 3.2 互換（H8）

`mapfile` を `while IFS= read -r` に置換し、`SH_FILES=()` を事前初期化する。
shebang を `#!/usr/bin/env bash` に統一する（`commit-merge.sh` も同様）。

### D2: shellcheck の導入と「無言スキップ」の解消（H8）

- `.devcontainer/Dockerfile` の apt install に `shellcheck` を追加する
- **未インストール時は skip ではなく警告**にする。`RAN_ANY` にも数えない。
  「検査対象が無い」のと「検査系が入っていない」のは意味が違う

ただし**未インストールを失敗（exit 1）にはしない**。
ホスト環境で `/commit-merge` を回す運用があり、そこで完了ゲートが常時閉じると
作業が進まなくなるため。警告を目立たせ、最後のサマリに未実行検査を列挙する。

### D3: 検査対象の拡張（H8）

| 対象 | 現状 | 変更 |
|---|---|---|
| `scripts/qa/*.py` | `TARGETS` が `src` `tests` 固定で対象外 | 存在すれば `TARGETS` に加える |
| `claude-san` | 拡張子が無く `git ls-files '*.sh'` に非マッチ | **shebang が sh/bash のトラッキング済みファイル**を対象にする |

### D4: 実行された検査／されなかった検査を最後に必ず表示する

**これが本 issue の核心。** 現状は「All quality checks passed」しか出ないため、
実際には1件しか動いていないことに気づけない。

```
=== All quality checks passed ===
  実行: rules MANIFEST 整合, スキル参照名の実在, スキルのラベル定義
  未実行: shellcheck（未インストール）, Python 検査（pyproject.toml が無い）
```

未実行がある場合は**必ず列挙する**（無言の切り捨て禁止。#117〜#119 の踏襲）。

### D5: CI（GitHub Actions）— **撤回**

当初は `.github/workflows/quality.yml` を追加して backstop にする設計だったが、
**ユーザー判断により CI は使わない**ことになったため撤回した（実装済みだったものを削除）。

- 直接の契機: gh トークンに `workflow` スコープが無く push が拒否された
- ユーザーの回答: 「CI は使わない」

3点対称（install ITEMS / SYNC_TARGETS / contribute-detect）への登録と
`release-export.sh` の除外も併せて撤去した。

## Fallback ホワイトリスト

- D2 の「shellcheck 未インストールでも exit 1 にしない」のみ。
  **警告表示とサマリへの列挙を必須**とし、無言にしない。

**auto-reviewer による当初の許可条件**:

1. **D5 の CI が同一 issue で実際に入ること。** 「どこかで必ず検査が走る」という
   前提が崩れると、この Fallback は単なるゲートの緩和になる
2. 未実行がある場合、最終バナーを素の `All quality checks passed` にせず
   **`passed（未実行あり: N件）`** の形にする

### ★ 条件1 からの逸脱（記録）

**CI は使わないというユーザー判断により、条件1 は満たせなくなった。**
黙って緩和を残さず、backstop を差し替えたうえで逸脱を記録する。

| 項目 | 内容 |
|---|---|
| 差し替えた backstop | **devcontainer**（`.devcontainer/Dockerfile` が shellcheck を導入する） |
| 根拠 | 本テンプレートの標準作業環境は devcontainer であり、そこでは必ず検査が走る |
| 残るリスク | **ホストで作業した場合、shellcheck が走らないまま完了ゲートを通過しうる** |
| 緩和策 | 警告の明示、未実行としてのサマリ列挙、「devcontainer で再実行するか手元に導入せよ」の案内 |
| 条件2 | **維持**（未実行があれば `passed（未実行あり: N件）`） |

**この逸脱を受け入れられない場合の代替**は「shellcheck 未導入で exit 1」だが、
ホスト作業時に完了ゲートが常時閉じるため採らなかった。

## 実装条件（auto-reviewer）

- **D1**: bash 3.2 ＋ `set -u` では空配列の `"${arr[@]}"` 展開自体がエラーになる。
  while-read 版でも「件数を確認してから展開」のガードを維持すること
- **D3-a**: `claude-san` を shellcheck 対象に入れると既存の指摘でゲートが赤になる。
  **本 issue 内で解消すること**（さもなくばマージ直後から完了ゲートが閉じる）
- **D3-b**: shebang 判定は `*.sh` 既収集分を除外し、先頭行のみ読み、
  `env python3` 等を誤検出しない正規表現にすること
- **D3-c**: テンプレート自体に `pyproject.toml` が無いため `scripts/qa/*.py` は
  ローカルでは実質未検査のまま。**CI 側で standalone 実行**（`uvx ruff check scripts/qa` 等）
  するか、follow-up issue に落とすかを実装時に確定し、記録すること
- **D4**: 検査名の蓄積は bash 3.2 互換のため**改行区切り文字列**で行う。
  「検査系が未導入」は `skip` とは別関数（`warn_missing` 等）に分離する
- **D5**: 軽量単一ジョブ・`concurrency` で cancel・トリガ最小化。
  **workflow 冒頭に無効化手順のコメントを必ず書く**（private 派生の Actions 枠への配慮）。
  `template-contribute-detect.sh` の対称性コメントも更新する

## 検証チェックリスト

- [ ] V1: macOS（bash 3.2）で shellcheck を導入した状態でも quality-check が完走する
      （`mapfile` の異常終了が起きない）
- [ ] V2: shellcheck 未インストール時、警告が出て `未実行` に列挙され、exit 0 は維持
- [ ] V3: `claude-san` が shellcheck の対象に含まれる
- [ ] V4: `scripts/qa/` があるとき Python 検査の対象に含まれる（pyproject があれば）
- [ ] V5: サマリに「実行した検査」と「未実行の検査（理由つき）」が必ず出る
- [ ] V6: CI ワークフローが構文的に妥当（`yq`/`python -c` でパース）で、
      install.sh の ITEMS・template-sync・contribute-detect の3点対称に含まれる
- [ ] V7: 既存3検査（MANIFEST / skill-refs / skill-labels）が引き続き機能し、
      いずれかを壊すと exit 1 になる
- [ ] V8: quality-check 自体が shellcheck を通る（自分が検査対象に入るため）
- [ ] V9: **positive control** — shellcheck 違反を含むフィクスチャを置くと exit 1 になる
- [ ] V10: shebang 判定の両方向 — シェルスクリプトは対象に入り、
      `#!/usr/bin/env python3` のファイルは対象に入らない
- [ ] V11: `scripts/commit-merge.sh`（shebang を変更する）が引き続き動作する

## 実装記録

### D3-c の決着: quality-check.sh 内で standalone ruff を実行する（follow-up issue にはしない）

`pyproject.toml` が無い場合、`ruff` が PATH にあれば
`ruff check --isolated --select E9,F <targets>` を実行する。CI では `uv tool install ruff`
で ruff を入れるため、テンプレート本体でも `scripts/qa/*.py` が**実際に検査される**
（実測: 11ファイル PASS）。ruff が無い環境では `warn_missing` として未実行に列挙する。

- **CI 側だけに検査を書かない**理由: 検査内容の単一情報源を `quality-check.sh` に保つため。
  CI は「ツールを入れて quality-check.sh を呼ぶ」だけにする
- **`--select E9,F` に固定する**理由: ruff の既定ルールセットはバージョン更新で増える
  （0.16 では `BLE001` `PIE790` `S110` `RUF059` が既定に入り、`scripts/qa` は10件の指摘を受ける）。
  バージョン固定なしに既定ルールへ委ねると、**ある日突然テンプレートの完了ゲートが赤くなる**（KI-D08）。
  構文エラー（E9）と pyflakes（F）は安定しており、「動かないコード」を検出するという目的に足りる
- `pyproject.toml` がある派生プロジェクトでは従来どおり `uv run ruff` を使い、
  `TARGETS` に `scripts/qa` が加わる（そちらはプロジェクトの ruff 設定に従う）

### D3-a の範囲拡大: `claude-san` 以外にも既存指摘があった

`claude-san` 自体は指摘0件だった（実測）。一方、**既に対象だったはずの `*.sh` 28ファイルに
23件の指摘**が存在した（shellcheck が未インストールで一度も走っていなかったため）。
CI を入れると初日から赤になるので、D3-a の趣旨に従い**本 issue 内で23件すべてを解消**した。

### 派生した修正

- `scripts/release-export.sh`: 同梱 CI を成果物から除外（`scripts/` を除外する成果物に
  `quality-check.sh` を呼ぶ workflow だけ残ると参照切れになるため）。
  併せて `usage()` の固定行番号（`sed -n '2,32p'`）を awk 方式に変更（ヘッダ追記で末尾が切れたため。#118/#119 と同型）
