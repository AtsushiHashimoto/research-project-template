# Issue #141 自動判断ログ

## メタ情報
- 判断日時: 2026-08-03
- 自動処理: /task-run（親 task #139）
- 判断対象: `.spec/issues/141-non-root-user.md`（コンテナ主プロセスの非 root 化）

## 必読コンテキストの状態

| ファイル | 状態 |
|---|---|
| `.spec/core-rules.md` | 既定節あり。**プロジェクト固有節は未記入** |
| `.spec/invariants.md` | 既定節あり。**プロジェクト固有節は未記入** |
| `.spec/known-issues.md` | 既定節あり。**プロジェクト固有節は未記入** |

→ S1 非該当（既定節が揃っている）。プロジェクト固有のルールが未登録のため、
既定のみで判断した。プロジェクト固有の失敗パターンは既定では捕捉できない。

## ゴール書き換えチェック（最優先）

親 task #139 の goal（成功条件 1〜5、negative の意味）を仕様と照合した。
仕様は goal 条件4「主プロセスが非 root になり、/workspace に root 所有ファイルが
残らない」および条件5の一部（uv PATH、CPU/GPU 起動）に対応する実装であり、
**goal の範囲・成功条件の変更を含まない**。→ 書き換えなし。

## 判断一覧

### 1. D1: uv を UV_INSTALL_DIR=/usr/local/bin へ

| 項目 | 内容 |
|------|------|
| 質問 | 設計が妥当か。見落としている副作用はないか |
| 判断 | ✅ 許可 |
| 理由 | (a) `/usr/local/bin` は既定 PATH に含まれ、`ENV PATH="/root/.local/bin:..."` の削除で「USER 切替後に uv が消える」障害を根本解決する。対症療法（symlink 二重管理）を退けた理由が単一情報源の原則（dev-guidelines / R-D06 の趣旨）で明示されている。(b) `python:3.11-slim` での実測（インストール先・残骸なし・nobody からの実行成功）が記録済みで、推測ではなく検証に基づく。(c) 現物確認: post-create.sh / post-start.sh / compose に `/root/.local/bin` への参照は無く、削除による他の破壊は見当たらない。 |
| 残る副作用（軽微・停止不要） | ① `uv self update` は /usr/local/bin が root 所有のため非 root では失敗する → NOPASSWD sudo（D3）で回避可能。② GPU ベースイメージ（nvcr.io/nvidia/pytorch）に uv が同梱されている場合は上書きになる → 挙動として問題なし。いずれも V7/V12 で検出可能 |
| 参照 | `.spec/known-issues.md` KI-D06（fresh 環境での再現）、dev-guidelines「単一情報源の原則」、Dockerfile:50-52 現物 |
| 自信度（参考記録） | 90% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 2. D2: 末尾で USER 切り替え（ビルドは root のまま）

| 項目 | 内容 |
|------|------|
| 質問 | 壊れる既存ワークフローがないか（features / updateRemoteUserUID / named volume / NVIDIA entrypoint） |
| 判断 | ✅ 許可 |
| 理由 | 指摘された4点を現物と照合した（下表）。既存パターン（Dockerfile:25 の `ARG USERNAME=vscode` を再利用、ユーザー名を2箇所に書かない）に沿っており、S5 非該当。 |
| 参照 | `.devcontainer/Dockerfile`、`docker-compose.yml`、`cpu/gpu devcontainer.json`、`post-create.sh`、`post-start.sh` |
| 自信度（参考記録） | 80% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

照合結果:

| 懸念 | 照合結果 |
|---|---|
| devcontainer features | D4 の主張どおり、features は派生ビルドで root として導入される。`docker-outside-of-docker` の socket 権限調整スクリプトは非 root 時に sudo を使う実装であり、D3（NOPASSWD 維持）が前提として噛み合っている。**D3 を外すと D4 が崩れる**依存関係にある点は仕様に明示されていないが、両方とも維持されるため実害なし |
| `updateRemoteUserUID: true` | remoteUser（vscode）が非 root であることが前提の機構であり、最終 USER の非 root 化とはむしろ整合する。compose が `USER_UID: ${UID:-1000}` を渡す既存経路も不変 |
| named volume `/home/vscode/.claude` | 新規 volume は root 所有でマウントされうるが、post-create.sh:11 の `sudo chown -R` が既にこれを処理している（本変更の前から必要だった処理）。壊れない |
| NVIDIA entrypoint | 非 root で完走するかは**未知**であり、仕様自身が「失敗と切り分け」表で「負の結果として記録」と定めている。これは goal の negative の意味（root 前提の結合の証拠）と正確に一致しており、R-D02 / experiment-discipline に適合 |
| `WORKDIR /workspace` | 実行時は bind mount で上書きされるため所有権の問題なし |
| post-create の sudo 6箇所 | D3 で NOPASSWD 維持のためそのまま動く。V10 が代理検証 |

### 3. 検証チェックリスト V1〜V15 の十分性

| 項目 | 内容 |
|------|------|
| 質問 | 「非 root 化が本当に達成されたか」を測る項目として十分か |
| 判断 | ⚠️ 警告付き許可（下記の追加項目を条件とする） |
| 理由 | V1〜V15 は全項目 PASS/FAIL を機械的に判定でき、S4 非該当。ただし親 goal 条件4の**後半「/workspace に root 所有ファイルが残らない」を直接測る項目が無い**。V5（id -u ≠ 0）は前半の代理にすぎない。また V5〜V11 は素の `docker run` であり、背景に書かれた実際の障害経路（`docker compose run` / devcontainer 実経路）を通らない。goal 条件5「CPU / GPU 両方で devcontainer が起動する」に対する CPU 側の実経路確認（postCreate / features を含む）も欠けている |
| 追加すべき項目 | V16: `docker compose run`（実際の compose 経路・entrypoint 込み）で `id -u` が 0 でない。V17: bind mount した /workspace 内にコンテナからファイルを作成し、**所有者が root でない**ことをホスト側から確認（goal 条件4後半の直接測定。macOS では UID 写像で偽陰性になり得るため、その旨を結果に併記する）。V18: `devcontainer up`（CPU）が完走する — features 導入・updateRemoteUserUID・postCreateCommand（sudo 6箇所）・postStartCommand（.bashrc 書込）を含む end-to-end 確認 |
| 参照 | 親 task #139 goal 条件4・5、`.spec/known-issues.md` KI-D03（silent-wrong: クラッシュしないため気づかれない失敗の類型。macOS で症状が出ない本件と同型） |
| 自信度（参考記録） | 75% ※停止判定には使用しない |
| 停止条件チェック | 該当なし（チェックリストは存在し判定可能。不足は追加で解消） |

### 4. V12（GPU）が完走しない場合の「未検証」+ user-action 方針

| 項目 | 内容 |
|------|------|
| 質問 | S1〜S8 の停止条件に該当しないか |
| 判断 | ✅ 許可（条件付き） |
| 理由 | 停止条件に**該当しない**。むしろ R-D05（実行0件を「通っている」と扱わない）に正しく適合している。「`docker build が通った` と書かない」という明示は、silent-wrong 系の失敗（KI-D01〜D04 の教訓）を先回りで塞ぐもの。S6 についても、これは negative を結論にする提案ではなく「未検証」を未検証のまま保留する提案であり、experiment-discipline の `unverified-negative` の扱いと同型で適合 |
| 条件 | ① V12 未検証のまま issue #141 を完了扱いにする場合、**user-action ラベル付きの follow-up issue を必ず起票**し、#141 と親 #139 の双方に「GPU は未検証」を明記すること。② 親 task #139 を閉じる際は goal 条件5（GPU 起動）が未充足のままになるため、その時点で **S7 の照合を改めて行う**（本判断は #141 の仕様の承認であり、#139 のクローズを承認するものではない） |
| 参照 | `.spec/core-rules.md` R-D02 / R-D05、`.claude/rules/template/experiment-discipline.md` §4、labels.md（user-action = 自動処理でスキップ） |
| 自信度（参考記録） | 85% ※停止判定には使用しない |
| 停止条件チェック | 該当なし（S7 は #139 クローズ時に再照合） |

### 5. スコープ外項目（NOPASSWD 維持など）が goal を小さく読んでいないか

| 項目 | 内容 |
|------|------|
| 質問 | スコープ外の設定が goal の範囲を勝手に狭めていないか |
| 判断 | ✅ 許可 |
| 理由 | スコープ外4項目を goal 条件 1〜5 と1項目ずつ照合した。(a) NOPASSWD 維持: goal 条件4は「主プロセスの非 root 化」であり sudo の除去ではない。goal の negative の意味の節が「post-create の sudo 6箇所」を維持対象のワークフローとして明示しており、維持は goal と整合する。#64 での見送り判断も引用されている。(b) checksum 検証: goal 条件のいずれにも該当せず、#64 で判断済み。(c) `ENV PATH=/usr/bin`: Node.js 優先の既存設定で本件と独立。(d) docker-outside-of-docker: セキュリティ方針変更で goal 外。いずれも「先行の判断を根拠に後続を落とす」形ではなく、goal に無いものを goal に無いと言っているだけである |
| 参照 | 親 task #139 goal 原文、`docs/security.md` §7（NOPASSWD = 低リスク・devcontainer 標準） |
| 自信度（参考記録） | 90% ※停止判定には使用しない |
| 停止条件チェック | 該当なし（S8: 落とされた項目はいずれも親の完了条件に無いことを原文照合で確認） |

### 6. Fallback ホワイトリスト（なし）

| 項目 | 内容 |
|------|------|
| 質問 | Fallback なしの宣言は妥当か |
| 判断 | ✅ 許可 |
| 理由 | 「駄目なら root で続行」を明示的に禁止しており、R-D01（前提が崩れた入力を黙って受理しない）・KI-D03 に正しく適合。目的を無効化するフォールバックを入れない判断は保守的で正しい |
| 参照 | `.spec/core-rules.md` R-D01、`.spec/known-issues.md` KI-D03 |
| 自信度（参考記録） | 95% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

## 総合判定

**⚠️ 警告付き許可**（実装へ進んでよい）

条件:
1. 検証チェックリストに V16〜V18（判断3）を追加すること
2. V12 未検証で完了する場合は user-action の follow-up issue を起票し、#141 / #139 に「GPU 未検証」を明記すること（判断4）
3. 親 task #139 のクローズ時に goal 条件5 の充足を S7 で再照合すること

## 停止判断

該当なし（S1〜S8 のいずれにも該当しない）。

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] D4（features は影響を受けない）は D3（NOPASSWD 維持）に依存する。将来 NOPASSWD を外す変更をする際は docker-outside-of-docker の socket 権限調整が壊れる可能性を再評価すること
- [ ] `uv self update` は /usr/local/bin が root 所有のため非 root では失敗する（sudo で回避可能。実害は小さいが、ユーザーが踏んだら docs に注記する）
- [ ] V17 は macOS ホストでは UID 写像により偽陰性になり得る。Linux ホストでの確認が取れない場合はその旨を結果に併記する
- [ ] `.spec/` 3ファイルのプロジェクト固有節が未記入のまま判断した（既定のみで判断）
