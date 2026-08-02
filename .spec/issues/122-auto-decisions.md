# Issue #122 自動判断ログ

## メタ情報
- 判断日時: 2026-08-02 09:45
- 自動処理: /task-run #115 経由（auto-reviewer, role: abstract-review）
- 対象仕様: .spec/issues/122-medium-low-cleanup.md
- 必読コンテキスト: .spec/core-rules.md / invariants.md / known-issues.md（3ファイルとも既定節あり。
  **「プロジェクト固有」節は3ファイルとも未記入**のため、既定のみで判断した）

## 判断一覧

### 0. 棚卸し表（A〜L）の妥当性 — 「#116〜#121 で解消済み」除外の検証

| 項目 | 内容 |
|------|------|
| 質問 | #114 の Medium/Low のうち #116〜#121 で解消済みとして除外した判断は妥当か |
| 判断 | ⚠️ 警告付き許可（**棚卸し表の追補を必須条件とする**） |
| 理由 | 実ファイルを検証した結果、**#116〜#121 で解消されておらず、かつ A〜L にも入っていない項目**を確認した（下記）。このまま #122 を閉じると、task #115 の goal「Medium/Low がまとめ issue で処理済み」が事実に反する。KI-D15（現状認識のずれの引き継ぎ）に該当する形の取りこぼし |
| 参照 | #114 本文、#116〜#121 の完了コメント、.devcontainer/docker-compose.yml、scripts/setup-worktree.sh、template-sync/SKILL.md、qa-*/SKILL.md |
| 自信度（参考記録） | 90% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

**実測で未解消と確認した取りこぼし（追補必須）:**

| 元深刻度 | 項目 | 現状の証拠 |
|---|---|---|
| Medium | docker-compose の無確認 bind mount（`${HOME}/.gitconfig` / `~/.config/gh`） | docker-compose.yml:23-24 に無条件マウントが残存 |
| Medium | setup-worktree.sh の実行ビット無し | `-rw-r--r--` のまま |
| Medium | .gitignore 同期の3点非対称 | template-sync/SKILL.md に .gitignore の処理が無い（install.sh 側のみ #116/#120 で更新） |
| Medium | .spec の decisions/subsystems に sync 経路なし | template-sync/SKILL.md に該当記述なし |
| Low | qa 3スキルの frontmatter 欠落 | qa-ask/qa-check/qa-setup の SKILL.md に frontmatter が無い |
| Low | agents/ 参照の `.claude/` 接頭辞欠落 | issue-diff / issue-gaps / issue-scan に `agents/...` 表記が残存（8箇所相当） |
| Low | release-export の除外に docs/surveys（判断の記録が無い） | doc-principles では surveys は公開成果物なので「意図的に含める」が正当だが、#114 が Medium 指摘した以上**判断を記録して閉じる**こと |

**条件**: 上記を (a) 本 issue のスコープに追加する、または (b) 「対応しない/別 issue」とする判断理由を棚卸し表に明記して follow-up issue を立てる。**黙って落とすことは不可**（採用時は対応する V 項目も追加）。

### 1. D1: `.dev/` の実体化

| 項目 | 内容 |
|------|------|
| 質問 | `.dev/.gitkeep` + `.dev/backlog.md` 雛形を追加し install ITEMS に含めてよいか |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | doc-principles.md の規約（.dev は git 管理、issue-backlog/unblock が参照）と一致し、release-export の除外に `.dev` が入っていることも確認した（release-export.sh:40）。**ただし** install.sh の --force はディレクトリをマージコピーする（`cp -r "$src/." "$dst/"`）ため、ITEMS に `.dev` を素朴に入れると **--force 再インストールで既存プロジェクトの backlog.md（ユーザーデータ）が雛形で上書きされる** |
| 条件 | `.dev/backlog.md` は「存在しない場合のみ作成」とすること（.spec/issues の特別扱いと同様の配慮）。V1 に「--force 再実行で既存 backlog.md の内容が保持される」を追加 |
| 参照 | install.sh:163-215、doc-principles.md、release-export.sh、issue-backlog/SKILL.md |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 2. D2: QA データの移設（docs/qa → .dev/qa）

| 項目 | 内容 |
|------|------|
| 質問 | config.py の既定値変更が既存プロジェクトの QA データを「見えなくする」破壊的変更にならないか。移行の考慮が必要か |
| 判断 | ⚠️ 警告付き許可（**レガシーパス検出を必須条件とする**） |
| 理由 | 移設自体は doc-principles 規約・リリース混入防止の両面で正当。しかし QAConfig.load は `.claude/qa-config.yaml` に `qa_dir` が無ければ既定値を使うため、既定値変更だけだと**既存プロジェクトでは bot/スキルが黙って空の `.dev/qa` を見始め、docs/qa の既存データが無言で無視される**。これは R-D01 / KI-D03（前提が崩れた入力を黙って受理）と同型の silent-wrong であり、無対策では禁止相当。なお qa-setup が書く yaml の例は `questions_file`/`answers_file` キーで、config.py の `qa_dir` と一致していない（既存 config は qa_dir を持たない可能性が高い）ため、既定値変更の影響は広い |
| 条件 | (1) 起動/読込時に「`.dev/qa` が無く `docs/qa/questions.jsonl` が存在する」場合、**黙って旧パスへフォールバックせず**、明示的に検出して案内または移行する（loud に）。(2) config.py だけでなく **bot.py:28 / watcher.py:22 のハードコード既定値**、`commit-push`、`rules/template/skills.md` の記述も追随する（V2 の「参照 0」が担保）。(3) 検証に「レガシーデータありのフィクスチャで黙って切り替わらないこと」を追加 |
| 参照 | scripts/qa/config.py、bot.py、watcher.py、qa-setup/SKILL.md、core-rules.md R-D01 |
| 自信度（参考記録） | 80% |
| 停止条件チェック | 該当なし（条件を満たさない実装は R-D01 違反として禁止） |

### 3. D3: TEMPLATE_REPO の一元化

| 項目 | 内容 |
|------|------|
| 質問 | `.claude/template-source.json` への一元化は妥当か |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | SSOT 化は dev-guidelines と一致。install.sh 自身に定義を残す理由（ブートストラップ）も妥当。ただし実測ではハードコードは **5箇所**（install.sh / template-sync SKILL / template-contribute SKILL / scripts/template-sync-rules.sh / scripts/template-contribute-detect.sh）であり、仕様の「スキル側」だけでは **scripts 2本が漏れる** |
| 条件 | (1) scripts/template-sync-rules.sh と scripts/template-contribute-detect.sh も読込側に含める（V4 の対象に明記）。(2) 既存派生プロジェクトには template-source.json が**存在しない**。不在時にハードコード既定へフォールバックするなら、それは「設定のデフォルト値」としてホワイトリスト登録が必要（現仕様は「Fallback なし」と宣言しており不整合になる）。登録するか、不在時は明示エラー＋再 install 案内とするか、どちらかを仕様に明記 |
| 参照 | grep 実測（5箇所）、auto-reviewer Fallback 分岐表 |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 4. D4: 既定ブランチ main 固定の規約化＋握り潰し除去

| 項目 | 内容 |
|------|------|
| 質問 | 検出せず main 固定と規約化し `\|\| true` をやめる判断は妥当か。master 運用組織で使えなくなるリスクとの比較 |
| 判断 | ✅ 許可 |
| 理由 | (1) 実害の本質は commit-merge.sh:77 の `git checkout main 2>/dev/null \|\| true` が失敗を握り潰し、**feature ブランチに居たまま pull・後続処理が走る**こと。除去は R-D01（前提が崩れたら raise）と R-D06（対症療法の禁止）に整合する。(2) master 運用リポジトリは**現状でも黙って壊れている**（checkout 失敗→握り潰し）。規約化＋明示エラーは「使えなくなる」のではなく「壊れ方が silent から loud に変わる」だけで、厳密に改善。(3) 検出（symbolic-ref）は origin/HEAD 未設定・ローカル専用リポジトリで失敗し、新たな分岐と失敗モードを持ち込む。テンプレートは worktree 運用・ブランチ削除処理等で既に main を全面に前提しており、規約の明文化が実態に一致 |
| 推奨（非条件） | エラーメッセージに「テンプレートは main 固定（git-workflow.md 参照）」と出すと master 利用者が原因に到達しやすい。master 対応が将来必要なら設定化を別 issue で |
| 参照 | scripts/commit-merge.sh:60-95、core-rules.md R-D01/R-D06 |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

### 5. D5: docs/security.md の更新

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | 実装確認済み: alias は Dockerfile に無く、post-start.sh が `claude()` ラッパーを .bashrc に注入している（post-start.sh:9-31）。security.md は alias 前提の記述が7箇所以上残存しており、実装と乖離。ドキュメントを実装に合わせるのは正当（実装側の挙動変更なし） |
| 参照 | docs/security.md、.devcontainer/post-start.sh |
| 自信度（参考記録） | 95% |
| 停止条件チェック | 該当なし |

### 6. D6: issue-scanner のブランチ判定

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | 現状 `grep "feature/${ISSUE_ID}"` は dev-guidelines の5接頭辞のうち4つを取りこぼす。`grep -E "/${ISSUE_ID}-"` は全接頭辞に対応し、`-` 終端により #5 と #55 の誤マッチも防ぐ。ISSUE_ID は数値なので正規表現エスケープ不要 |
| 参照 | .claude/agents/issue-scanner.md:69、dev-guidelines.md |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

### 7. D7: devcontainer 表示名・hostname、マジックナンバー

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ 警告付き許可 |
| 理由 | `name` は cpu/gpu の devcontainer.json にあり `${localWorkspaceFolderBasename}` が使える。**しかし `hostname: devcontainer` と `shm_size: "8gb"` は docker-compose.yml にあり、`${localWorkspaceFolderBasename}` は devcontainer.json 専用変数で compose ファイルでは展開されない**（compose はホストシェルの環境変数のみ）。素朴に書くと空展開または文字列そのままになる |
| 条件 | hostname 側は別手段を取ること（例: compose の hostname 指定を削除して既定に任せる、環境変数 `${...:-devcontainer}` 経由等）。**実機（devcontainer 起動）で確認するまで V9 を PASS にしない**。マジックナンバーへの根拠コメントは無条件で許可 |
| 参照 | .devcontainer/docker-compose.yml、.devcontainer/cpu/devcontainer.json |
| 自信度（参考記録） | 75% |
| 停止条件チェック | 該当なし |

### 8. D8: --force 時の shared_data_path 等の復元

| 項目 | 内容 |
|------|------|
| 質問 | 「復元」が正しいか、「上書きしない（コピー自体をスキップ）」が正しいか（INV-D03 関連） |
| 判断 | ✅ 許可（「復元」を支持） |
| 理由 | 「上書きしない」（worktree-config.json を --force 対象から外す）だと、テンプレート側のスキーマ進化（新フィールド追加）が既存プロジェクトに届かなくなる。「テンプレートで上書き→ユーザーデータのフィールドのみ選択的に復元」は created_at で確立済みの機構の一貫した拡張であり、スキーマ更新とデータ保全を両立する。INV-D03（データ保存先の保護）に整合し、silent reset（KI-D03 同型）を塞ぐ。invariants への抵触なし——むしろ遵守側の変更 |
| 実装注記（準条件） | (1) `shared_data_path` はパス文字列で `&` `\|` 等を含み得るため、created_at と同様 **sanitize_sed を必ず適用**。(2) 旧スキーマでフィールドが無い場合は created_at と同じ `${PREV:-テンプレート値}` 方式（設定の既定値でありホワイトリスト該当）。(3) V10 のフィクスチャに特殊文字を含むパスを入れる |
| 参照 | install.sh:178-186, 296-310、invariants.md INV-D03 |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 9. D9: template-sync の新規ファイル検出

| 項目 | 内容 |
|------|------|
| 質問 | 変更が既存 sync 挙動を壊さないか |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | 現状の `diff -rq ... 2>/dev/null` はローカルに対象が無いとエラーごと握り潰す（R-D01 同型の silent 欠陥）。修正は「報告が増える」方向の追加であり、Step 7 には既に「新規ファイル: 追加するか確認」の下流フローが存在するため、検出を直しても処理経路は既存のまま。既存ファイルの diff 挙動を変えなければ後方互換 |
| 条件 | (1) `2>/dev/null` の全面除去ではなく、**存在チェックで「新規」を明示報告**する実装とする（stderr 全開放は無関係なノイズを混ぜる）。(2) D1 で `.dev` を install ITEMS に足しても **SYNC_TARGETS には `.dev` を入れない**こと（backlog.md はユーザーデータで、sync に載せると「変更あり」の偽差分と雛形上書きの提案を恒久生成する）。ITEMS/SYNC_TARGETS の対称性コメントに、この非対称が意図的である旨を明記 |
| 参照 | template-sync/SKILL.md:195-245、#121 引き継ぎコメント |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 10. D10: shebang の統一

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | 残存6ファイルを実測確認（claude-san / install.sh / setup.sh / post-create.sh / post-start.sh / start-bot.sh）。機能等価で低リスク |
| 注記 | claude-san は拡張子無しのため、V12 の検査は `*.sh` 限定にせず `git ls-files` 全体の先頭行を見ること（仕様の書き方どおりで正しい。実装時に狭めないこと） |
| 自信度（参考記録） | 95% |
| 停止条件チェック | 該当なし |

### 11. V1〜V13 の十分性

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ 警告付き許可（追加を条件とする） |
| 理由 | 既存の13項目はいずれも PASS/FAIL 判定可能（S4 非該当）。ただし上記条件を担保する項目が不足 |
| 追加必須 | V14: --force 再実行で既存 `.dev/backlog.md` の内容が保持される（D1）。V15: legacy `docs/qa` データが存在するフィクスチャで、黙って `.dev/qa` に切り替わらない＝検出・案内が出る（D2）。V16: template-source.json **不在**時の挙動が仕様どおり（明示エラー or 登録済みフォールバック）（D3）。V10 に特殊文字パスのフィクスチャ（D8）。V4 の対象に scripts 2本を明記（D3）。棚卸し追補を採用した項目の V |
| 注記 | V9 は静的検査で PASS にできない（compose 変数展開の実機確認が必要） |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

## ゴール書き換えチェック

- 親 task #115 の goal の書き換え: **なし**（仕様は goal を維持）
- ただし判断0のとおり、棚卸しの取りこぼしを黙って確定させると「Medium/Low 処理済み」という goal 達成判定が事実に反する（**暗黙のスコープ縮小**）。条件として追補を義務付けることで回避する

## 停止判断

- 該当した停止条件: **なし**（S1: 3ファイルとも既定節あり / S2: goal 確定済み / S3: invariants 抵触なし、D8 はむしろ INV-D03 遵守側 / S4: チェックリストあり・判定可能 / S5: 既存パターン踏襲（created_at 復元機構・Step7 新規ファイルフロー等の拡張）/ S6: experiment 非該当）
- 処理は**前進可**。ただし各判断の「条件」は実装・検証で必須

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] `.spec/` 3ファイルの「プロジェクト固有」節が未記入のため、既定のみで判断した（判断確度低下の自覚として記録）
- [ ] D7 の hostname 可変化は実機確認まで未確定（compose の変数展開制約）
- [ ] release-export と docs/surveys の関係（公開成果物として意図的に含めるなら、その判断を棚卸しに記録）
- [ ] master 既定ブランチ対応の要否（必要になった場合は設定化を別 issue で。D4 の規約化とは独立）
