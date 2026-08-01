# Issue #116 自動判断ログ

## メタ情報
- 判断日時: 2026-08-01
- 自動処理: /task-run（task #115 配下）
- 判断対象: .spec/issues/116-install-bootstrap.md（D1〜D6 ＋ Fallback ホワイトリスト1件）
- 必読コンテキスト: .spec/core-rules.md / invariants.md / known-issues.md（3ファイルとも存在、既定節あり。
  **「プロジェクト固有」節は3ファイルとも未記入**のため、既定のみで判断した。停止条件 S1 には該当しない）

## 判断一覧

### 1. D1: GITIGNORE_ENTRIES の修正（C1）

| 項目 | 内容 |
|------|------|
| 質問 | install.sh:268 の `.worktrees/` → `worktrees/` 修正＋ `.claude/rules/template.bak-*/`・`.claude/model-policy.local.json` の追加 |
| 判断 | ✅ 許可 |
| 理由 | 現状コードで誤記を確認（install.sh:268 は `.worktrees/`、テンプレート .gitignore:2 とルール群は `worktrees/`）。worktree 一式がコミット対象になるデータ保護欠陥の修正で、INV-D01/D02（worktree 運用）の前提を守る側の変更。追加2エントリはテンプレート .gitignore（78行・83行）に既に存在するワークフロー生成物で整合。GITIGNORE_ENTRIES とテンプレート .gitignore の二重管理（SSOT違反）は残るが、恒久策を #122 に明示的に委譲しており、task goal（Medium/Low はまとめ issue で処理）と整合 |
| 参照 | install.sh:266-290、.gitignore:2,78,83、invariants.md INV-D01/D02、dev-guidelines「単一情報源の原則」 |
| 自信度（参考記録） | 95% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 2. D2: setup-labels の自動実行（H2）

| 項目 | 内容 |
|------|------|
| 質問 | install.sh の初期化を init-data.sh 直呼びから3点実行（configure-worktree-paths → setup-labels → init-data）に変更。ラッパー直呼びではなく install.sh 内で3スクリプトを順に呼ぶ |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | 3点実行の順序は worktree-init/init.sh（既存パターン）と同一であり、labels.md の「新規プロジェクトでは自動実行」宣言との不整合（H2）を解消する。**警告**: 初期化シーケンスの定義が worktree-init/init.sh と install.sh の2箇所になり SSOT が崩れる。仕様は「カレントディレクトリ問題」を理由に挙げるが、install.sh は L174 で `cd "$PROJECT_ROOT"` 済みでありラッパー直呼びが本当に不可かは未検証。実装時に (a) ラッパー直呼びで動くならそちらを優先、(b) 複製する場合は両ファイルに相互参照コメントを必ず入れ「片側だけ直さない」ことを明記すること |
| 参照 | .claude/skills/worktree-init/init.sh、install.sh:309-324、labels.md 冒頭、dev-guidelines「単一情報源の原則」 |
| 自信度（参考記録） | 80% ※停止判定には使用しない |
| 停止条件チェック | 該当なし（S5 は「理由が仕様に書かれていない」場合。本件は理由が明記されている） |

### 3. Fallback ホワイトリスト: setup-labels 失敗でも install 続行＋案内

| 項目 | 内容 |
|------|------|
| 質問 | gh 未認証等で setup-labels が失敗しても install 全体は落とさず、「後で bash scripts/setup-labels.sh を実行せよ」と案内する |
| 判断 | ✅ 許可（条件付き） |
| 理由 | R-D01/KI-D03（前提が崩れた入力を黙って受理しない）の禁止対象は **silent** fallback。本件は必ず案内メッセージを出す明示的な graceful degradation であり、握り潰しではない。gh 未認証は install 時点で正常にありうる状態で、install の主目的（ファイル配置）とラベル作成は独立。setup-labels.sh 自体も gh 不在/非リポジトリを既に明示メッセージ付きで処理している（L18-19）。既存の worktree-init/init.sh の `|| true` より丁寧（案内必須）。**条件**: 案内メッセージの出力は V3 で必ず検証すること。メッセージ無しの `|| true` に劣化したら R-D01 違反として禁止 |
| 参照 | core-rules.md R-D01、known-issues.md KI-D03、scripts/setup-labels.sh:18-19、auto-reviewer Fallback 分岐表 |
| 自信度（参考記録） | 90% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 4. D3: sed -i の BSD/GNU 互換化（H3）

| 項目 | 内容 |
|------|------|
| 質問 | install.sh:238-241 と setup.sh:20-27 の `sed -i` を `sed -i.bak ... && rm -f file.bak` 形式に変更 |
| 判断 | ✅ 許可 |
| 理由 | 現状コードで GNU 形式を確認。`-i.bak`＋rm は BSD/GNU 両対応の標準イディオムで、新規依存なし・既存パターン（post-create.sh:29 も `sed -i` だが Linux コンテナ内専用なので対象外で正しい）と整合。KI-D06（fresh 環境で動かない）系の環境依存欠陥の根本修正であり対症療法ではない |
| 参照 | install.sh:238-241、setup.sh:20-27、known-issues.md KI-D06 |
| 自信度（参考記録） | 95% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 5. D4: claude-san の扱い（H1）

| 項目 | 内容 |
|------|------|
| 質問 | claude-san は配布せず（ITEMS 非追加）、post-create.sh:38 の symlink を `[ -f "$(pwd)/claude-san" ] &&` でガード |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | 現状、install 派生には claude-san が配布されておらず dangling symlink が作られる。ガード追加は現状の機能を何も減らさず（テンプレート本体・clone 派生では claude-san 存在を確認済み、従来どおり動作）、install 派生の欠陥のみ除去する。配布しない判断は #51 クローズ（task-run 系自動化が主線）と整合的で、依存を増やさない方向は「既存優先・必要最小限」の基準に合う。**警告**: post-create.sh は `set -e` のため、ガードの実装は `[ -f ... ] && cmd` 単文ではなく `if [ -f ... ]; then ... fi` を推奨（&& 短絡がスクリプト末尾や終了コードに影響する事故を防ぐ。現状 L38 は末尾ではないが、将来の行移動に対して頑健にする） |
| 参照 | .devcontainer/post-create.sh:6,38、install.sh ITEMS（163-172、claude-san 非含有を確認）、リポジトリ直下 claude-san の存在確認、issue #51 の記載（仕様内引用） |
| 自信度（参考記録） | 85% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 6. D5: template-substitutions.json 生成の修正（Medium）

| 項目 | 内容 |
|------|------|
| 質問 | 生成ブロックを「CLAUDE.md 不在」分岐の外へ移動、非対話・全値空なら書き出さない |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | 現状（install.sh:208-263）は既存 CLAUDE.md 保持時に substitutions.json が生成されず、非対話時は全値空の json を書き出す。「存在するのに無効」なファイルは silent-wrong（R-D01/KI-D03 の親類）であり、空値時に書き出さない方針は正しい。**警告（実装上の穴）**: 値を集める対話プロンプト（L216-247）も「CLAUDE.md 不在」分岐の内側にある。生成ブロックだけ外に出しても、既存 CLAUDE.md 保持ケースでは値が空のままで V5（既存 CLAUDE.md 持ち＋対話時に生成される）を満たせない。**対話時は既存 CLAUDE.md の有無に関わらず値の収集も行う**必要がある。V5 が期待挙動を pin しているので実装はこれに従うこと。また「対話だが空値のまま Enter 連打」の場合の扱い（デフォルト値が入るため実質空にならない現実装の挙動）を維持すること |
| 参照 | install.sh:208-263、core-rules.md R-D01、known-issues.md KI-D03、仕様 V5 |
| 自信度（参考記録） | 75% ※停止判定には使用しない |
| 停止条件チェック | 該当なし（V5 は PASS/FAIL 判定可能なので S4 非該当） |

### 7. D6: setup.sh の整理（Medium）

| 項目 | 内容 |
|------|------|
| 質問 | 死んだ sed（{{CREATED_AT}}/{{UPDATED_AT}}）削除、worktree-config.json に実行時刻を書き込み、プレースホルダ置換を install.sh と同じサニタイズ付きロジックに揃える |
| 判断 | ✅ 許可 |
| 理由 | worktree-config.json の実体（created_at: "2026-03-11T16:02:06Z" 固定リテラル）を確認。プレースホルダは存在せず setup.sh:26-27 の sed は確実に no-op（死んだコード）。固定タイムスタンプは偽情報であり、実行時刻の書き込みは根本修正（R-D06 の対症療法禁止に合致する正しい方向）。setup.sh:20-23 はサニタイズ無し＋ `s/../..` 区切りのため `/` や `&` を含む入力で壊れる — install.sh の sanitize_sed ロジック（既存パターン）への統一は既存優先の基準どおり。完全1本化を #122 に委譲する範囲設定も task goal と整合 |
| 参照 | setup.sh:20-27、.claude/worktree-config.json:5-6、install.sh:234-241、core-rules.md R-D06 |
| 自信度（参考記録） | 90% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

## goal 書き換えチェック

- 親 task #115 goal「#114 の Critical/High が全て解消し、Medium/Low がまとめ issue で処理済み。再発防止チェックが入っている。既存の検証済み動作（#101 V1〜V11、#108 F1〜F6）を壊さない」
- 本仕様は C1/H1/H2/H3 を直接解消し、Medium 2件を扱い、恒久策（SSOT 化・setup.sh 廃止判断）を #122 に明示委譲。V7 で #108 F1/F5/F6 の回帰を確認する。
- **goal の書き換え・範囲変更・成功条件変更: なし**

## 停止判断

- 該当した停止条件: **なし**（S1〜S6 すべて非該当。前進する）
- S1: 3ファイル存在・既定節あり（プロジェクト固有節は未記入 → 下記に記録）
- S2: 親 task goal は確定済み・単一解釈
- S3: invariants / ADR 違反なし（INV-D01〜D05 と整合、むしろ INV-D01/D02 の前提を守る修正）
- S4: 検証チェックリスト V1〜V8 あり、全項目 PASS/FAIL 判定可能
- S5: 既存パターンと異なる点（D2 のラッパー非使用）は理由が仕様に明記されている
- S6: experiment ではない（negative 結論を扱わない）

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] **D6 / D3(setup.sh 側) の検証項目が V1〜V8 に無い。** 実装時に追加すること:
  - V9 相当: setup.sh 実行後、worktree-config.json の created_at/updated_at が実行時刻であり、{{CREATED_AT}} への死んだ sed が存在しない
  - V10 相当: setup.sh のプレースホルダ置換が BSD sed で動作し、`/` `&` を含む入力でも壊れない
- [ ] D2: ラッパー（worktree-init/init.sh）直呼びが本当に不可かを実装時に検証。可能ならラッパー呼びで SSOT を保つ
- [ ] D5: 対話プロンプトの移動（既存 CLAUDE.md 保持時も値収集）が仕様文面に明示されていない。V5 を正として実装
- [ ] D4: ガードは `if ... fi` 形式を推奨（set -e 下の && 短絡対策）
- [ ] `.spec/` 3ファイルの「プロジェクト固有」節が未記入のため、既定のみで判断した（判断確度への影響を自覚しておくこと）
