---
description: task 配下の issue を既定順で自動処理する（旧 /issue-auto）
argument-hint: <task番号>
---

# Task Run

**task 1つ分の仕事を自動で回す。** task の子 issue を GitHub ネイティブ sub-issue から解決し、
既定順（survey → spec → feature → validation → experiment）で順次処理する。

```
/task-run #101
```

**引数は task 番号のみ。** 子 issue の列挙と順序決定はスキルが行う。
人が issue ID を並べる方式をやめたのは、順序の指定ミスを原理的になくすため。

## ★★★ 完全自動モード ★★★

1. **ユーザー確認は最初の1回のみ**
2. **各 issue の完了時に確認しない** — 品質チェック通過で自動マージ
3. **エラー時のみ停止**
4. **途中で質問しない** — 判断が必要な場合は安全側に倒して続行

**禁止事項:**
- 「次の issue に進みますか？」と聞く
- 各 issue 完了時にユーザー入力を待つ
- **ステップの省略** — review-spec、auto-reviewer、品質チェックは絶対にスキップしない
- **並列化** — 各 issue は順次処理

### ★ 「安全側に倒す」の例外

以下は「安全側に倒して続行」してはならない。**停止すること。**

| 状況 | 理由 |
|---|---|
| **task の goal が未確定** | 空白を埋めて goal を発明すると、以降の全 issue がその上に積み上がる。安全側に倒しようがない。**「goal 自体（成功条件 / negative の意味）の未確定」を指す。担当が併記された下位パラメータの未確定は該当しない**（Step 0-2） |
| **未確定項目に解消担当が書かれていない** | 誰も確定させないまま実装に入る。担当を推測で補うと goal の発明と同じことが起きる（Step 0-2） |
| **未確定が解消されたか判定できない** | 判定基準なしに「影響しないだろう」と続行すると、事実上の続行 fallback になる（Step 0-2b） |
| **negative result のトリアージ未完了** | 実装バグを見逃して「効かない」と確定させる害のほうが大きい（後述 Step 4-2） |
| **goal の書き換えを含む提案** | ゴールの不変性に反する（`.claude/rules/template/issue-hierarchy.md` 参照） |
| **goal を小さく読む提案**（成功条件が未充足のままのクローズ／根拠を明示できない未着手の子の切り捨て） | 書き換えの逆方向で、同じく goal が実際より小さくなる。「上位が満たせないから下位も不要」は落とす理由にならない（`auto-reviewer.md` の S7 / S8） |

## Workflow

### Phase 0: 事前準備

#### Step 0-1: QA 回答の確認

```bash
QA_DIR=$(bash scripts/qa/qa-dir.sh)   # 旧 docs/qa にデータがあれば移行案内が出る
[ -f "$QA_DIR/questions.jsonl" ] && echo "QA回答を確認中..."
```

#### Step 0-2: task の妥当性確認

```bash
TASK=$1
LABELS=$(gh issue view "$TASK" --json labels -q '[.labels[].name]|join(",")')
echo "$LABELS" | grep -q "task" || { echo "#$TASK は task ラベルを持ちません"; exit 1; }
```

**★ goal が確定しているか確認する。**

**「未確定」節に項目が残っていること自体は停止理由にしない。**
データ入手可否・公表値の所在・許容差のように、**survey / spec を実施して初めて確定する項目**が
そこに入る。事前確定を要求すると「調べる前に答えを書く」ことになり、
`/task-start` の「答えられない項目は推測で埋めない」と矛盾する。

見るのは**未確定の有無ではなく、種類と担当の有無**である。

| # | 判定対象 | 動作 |
|---|---|---|
| G1 | 「目標の状態」節が無い、または**成功条件**が空欄 | **停止** |
| G1b | 成功条件が **PASS/FAIL の述語として1文に書き直せない**（測定対象・判定手段が特定できない） | **停止**（Phase Final の「1項目ずつ照合」が成立しないため、入口で止める） |
| G2 | **negative の意味**が空欄 | **停止** |
| G3 | 成功条件 / negative の意味が**委譲 placeholder のみ**（「spec で決める」「survey の結果次第」等）、**または未確定項目に言及する語句を削って読むと述語だけが残る**（「事前登録した基準を満たす」「判定が記録されている」等） | **停止**（実質空欄。**goal の実質を未確定に逃がす**抜け道を塞ぐ） |
| G4 | **成功条件 / negative の意味**に複数の解釈が残っている | **停止** |
| G5 | 「未確定」節が**存在しない、または空**（見出しのみ） | 未確定ゼロとみなし**続行** |
| G6 | 未確定項目に**解消担当が併記されていない** | **停止** |
| G7 | 併記された担当先が**実在しない**（そのラベルの子 issue が無い / その番号の issue が無い） | **停止** |
| G7b | 担当先が **`out-of-date` / `user-action` を持つ**（Step 0-3 でスキップされる）、または **`→ #番号` がこの task の子でない** | **停止**（この run で closed にならず、再照合が永久に走らないため） |
| G8 | 上記のいずれにも該当しない | **続行**（Step 0-2b で再照合する） |

**★ G3 の判定手順（最重要）。** これを機械的に行う。

未確定項目に言及する語句を成功条件から削って読み、**「何を作り、何を測るか」が残るか**を見る。

```
❌ 成功条件: 事前登録した合否基準を全て満たし、判定結果が記録されている
   → 「合否基準 → spec」を削ると「基準を満たし判定が記録されている」＝述語だけ。実質は spec が書く
✅ 成功条件: 比較表の全セルが埋まり、事前登録した許容差で判定されている
   → 「許容差 → spec」を削っても「比較表の全セルが埋まる」が残る。何を作るかは確定している
```

**この抜け道は差分に現れない。** 成功条件の文字列は最後まで変わらず、意味だけが後から埋まるため、
`auto-reviewer` の goal 書き換え判定にも Phase Final の照合にも PR 差分にも出ない
（`.spec/known-issues.md` KI-007 と同型）。**入口で止めるしかない。**

記述形式の定義は **`/task-start` Step 4 の「★ 「未確定」の記述形式（定義。他スキルはここを参照する）」が
単一情報源**。ここには再掲しない。

**節の見出しは前方一致で読む。** `## 未確定` のほか `## 未確定（推測で埋めない）` のように
補足が付いていても同じ節として扱う。

**担当の解決には子 issue 一覧が必要**なので、Step 0-3 を待たずにここで取得する。

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/issues/$TASK/sub_issues" \
  --jq '.[]|"\(.number)\t\(.state)\t\([.labels[].name]|join(","))"'
```

| 担当の記法 | 解決 |
|---|---|
| `→ <ラベル>`、同ラベルの子が1つ | その issue |
| `→ <ラベル>`、同ラベルの子が複数 | **全てが closed になった時点**で再照合 |
| `→ <ラベル>`、同ラベルの子が無い | **G7 で停止** |
| `→ #<番号>` | その issue |

**停止時は経路ごとに報告項目を変える。** 「未確定節を貼るだけ」では原因が分からない。

```bash
# G1〜G4（goal 自体が未確定）
gh issue comment "$TASK" --body "## ⚠️ 自動処理を開始できません

**task の goal が未確定**のため停止しました。

### 未記入・不十分な欄
[成功条件 / negative の意味 のどちらが空欄か。委譲 placeholder のみの場合はその文言を引用]

\`/task-start\` で目標を確定させてから再実行してください。"
exit 1

# G6 / G7（担当なし・担当先不在）
gh issue comment "$TASK" --body "## ⚠️ 自動処理を開始できません

未確定項目に**解消担当が無い / 担当先が実在しない**ため停止しました。

### 該当項目
[項目名と、担当欄の現状（未記入 / 実在しないラベル・番号）]

未確定節の各項目に解消担当を併記して再実行してください（task の作り直しは不要）。
記法は \`/task-start\` Step 4 を参照。"
exit 1
```

**推測で埋めて続行しないこと。** 担当が書かれていない項目を「たぶん survey だろう」と
みなして続行するのは、本ゲートの設計意図そのものに反する。

#### Step 0-2b: 未確定の再照合（担当 issue のクローズ直後）

**担当 issue が閉じた直後に、その issue が担当する未確定項目を1項目ずつ再照合する。**

Phase 1-N の Step 5（`/issue-finish`）の後、次の issue の Step 1 に進む前に実行する。
未確定を抱えたまま後続に進むと、実装が仮定の上に載り、後で覆ったときに
validation / experiment まで巻き戻る。

参照する成果物: `docs/surveys/`（survey）、`.spec/issues/`（spec）、および issue のコメント。

**★ 事前登録が前提の項目は、確定のタイミングも確認する。**

許容差・閾値・判定基準のように「データを見る前に決める」ことに意味がある項目は、
**成果物上の確定が実測より前**であることを確認する。実測後に確定していた場合は
「解消」とせず**停止**する。事後に決めた基準は事前登録ではなく、
結果に合わせて基準を動かしたのと区別がつかない。

| 再照合の結果 | 動作 |
|---|---|
| **解消された** | 成果物の**ファイルパスと該当記述**を確認し、`解消済み（→ #NNN, <path> §x）` に**書き換えて**続行。**明記が見つからない場合は「解消されず」として扱う** |
| **解消されたが、事前登録項目が実測後に確定していた** | **停止** |
| **解消されず、後続 issue の設計に影響する** | **停止** |
| **解消されず、影響するか判定できない** | **停止**（既定は停止。判定基準なしの続行は禁止） |
| **解消されないが影響しない** | 「解消不能」と**理由を記録**して続行。理由には**担当 issue の成果物の明示記述を引用**する |

**★ 書き込み範囲は「未確定」節のみ。**

確定した内容の本体は成果物（`docs/surveys/` / `.spec/issues/`）に書き、
task 本文には解消済みの印だけ残す。**「目標の状態」節は編集しない。**
これは自動処理が task 本文を編集する唯一の経路であり、範囲を限定しないと
ゴールの不変性（`auto-reviewer` の最優先判定）の抜け道になる。

```bash
gh issue comment "$TASK" --body "## ⚠️ 未確定が解消されていません

### 該当項目
- 項目: [項目名]
- 担当: #[番号]（closed）
- 解消されなかった理由: [成果物のどこを見て、なぜ確定できなかったか]
- 影響を受ける後続 issue: [番号と理由。判定できない場合は「判定不能」と明記]

### 求める判断
続行可否 / 担当の再割当 / task の中断"
exit 1
```

**「解消不能」は終端ではない。** 後続で実は影響すると判明した場合は、その時点で停止する
（negative result のトリアージと同種の例外）。

**★ 未確定項目の削除は、Step 0-2b の再照合を経た場合に限る。**

停止を解除する目的で項目を消してはならない。G6 / G7 の停止に対して
「担当を併記する」より「行を消す」（→ G5 で続行）ほうが機械的に安価なため、
制約を書かないと自動復帰が最短経路として削除を選ぶ。

**削除は行の消去ではなく `解消済み（→ #NNN, <path> §x）` への書き換えで行い、監査証跡を本文に残す。**

**★ Phase 0 では常に、既に closed の担当 issue に紐づく未解消項目を先に再照合する。**

`--from` の有無を問わない。**closed の子は Step 0-3 でスキップされる**ため、ここで拾わないと
再照合は永久に走らない。特に **Step 0-2b で停止した直後の素の再実行がまさにこの形**であり、
規定しないと**停止が自分自身を無効化する**（1回止まって、次の実行で無音で通る）。

参照するのは**マージ済みの main 上の成果物**とする。未マージなら「解消されず」として扱う。

#### Step 0-3: 子 issue の解決と順序決定

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/issues/$TASK/sub_issues" --jq '.[]|"\(.number)\t\(.state)\t\([.labels[].name]|join(","))\t\(.title)"'
```

**既定順で並べる:**

```
survey → spec → feature → validation → experiment
```

上記に該当しないラベル（`bug` `docs` `refactor` `chore`）は、その並びの後に番号順で処理する。

**closed の子はスキップ。** `out-of-date` / `user-action` ラベルを持つ子もスキップし、
ユーザーに通知する。

#### Step 0-4: スナップショット

```bash
SNAPSHOT_BRANCH="pre-task/$(date +%Y%m%d-%H%M%S)"
git branch "$SNAPSHOT_BRANCH" main
```

#### Step 0-5: ユーザー確認（唯一の確認点）

```
┌─────────────────────────────────────────────────────────────┐
│ /task-run #101 実行確認                                      │
├─────────────────────────────────────────────────────────────┤
│ task: 基礎検証                                               │
│ goal: <task の成功条件を引用>                                │
│                                                              │
│ 処理する子 issue（既定順）:                                  │
│   1. #102 survey     先行研究の調査                          │
│   2. #103 spec       仕様の作成                              │
│   3. #104 feature    実装                                    │
│   4. #105 validation 実装の動作確認                          │
│   5. #106 experiment 仮説検証                                │
│                                                              │
│ スナップショット: pre-task/20260731-160000                   │
│ 実行しますか？                                               │
└─────────────────────────────────────────────────────────────┘
```

### Phase 1-N: 各 issue の処理

#### Step 1: issue 着手

```
Skill(skill="issue-start", args="#${ISSUE_ID}")
```

worktree とブランチを作成する（`--relative-paths` を使用。理由は `.claude/rules/template/git-workflow.md` 参照）。

#### Step 1.5: 仕様レビュー（`/review-spec`）

**★★★ 絶対にスキップしない ★★★**

review-spec はユーザーとの対話ではなく**セルフチェック**である。

1. 既存仕様ファイル `.spec/issues/${ISSUE_ID}-*.md` を確認
2. 無ければ `/review-spec` を実行して生成
3. **auto-reviewer による代理判断**

```
Task(subagent_type="general-purpose", model="$(bash scripts/resolve-model.sh abstract-review)", prompt="
あなたは auto-reviewer エージェントです。
.claude/agents/auto-reviewer.md の定義に従って判断してください。

## 必ず読み込むコンテキスト
- .spec/core-rules.md
- .spec/invariants.md
- .spec/known-issues.md

## 親 task の goal（変更禁止）
${TASK_GOAL}

## 判断対象
${REVIEW_SPEC_RESULT}

## 出力
1. 各判断項目への回答（許可/禁止/警告付き許可）
2. 判断理由と参照コンテキスト
3. 自信度（%）（参考記録。停止判定には使わない）
4. 停止条件（auto-reviewer.md の S1〜S8）に該当する場合は「停止」を明示し、該当項目を記載
5. **提案が親 task の goal の書き換えを含む場合は「禁止」と判定**

判断ログを .spec/issues/${ISSUE_ID}-auto-decisions.md に出力してください。
")
```

停止条件（S1〜S8 の具体的欠落）に該当したら issue にコメントして停止する。

#### Step 2: 実装

```
Task(subagent_type="general-purpose", model="$(bash scripts/resolve-model.sh implementation)", prompt="
Issue #${ISSUE_ID} の実装を行ってください。

## 親 task の goal（この範囲を超えないこと）
${TASK_GOAL}

## Issue内容
${ISSUE_BODY}

## 仕様ファイル（必ず参照）
.spec/issues/${ISSUE_ID}-*.md

## 完了条件
1. 仕様ファイルの検証チェックリストを全て満たす
2. 承認済み Fallback ホワイトリスト以外の fallback を使わない
3. 必要なテストの追加

## 重要な制約
- **コミットは行わないでください**。後のステップで自動実行されます
- **親 task の goal を書き換えないでください**
")
```

#### Step 3: 進捗報告

```bash
gh issue comment $ISSUE_ID --body "## 実装完了

$(git diff --stat main)"
```

#### Step 4-1: コード品質チェック

Issue の種類ラベルに応じて検査範囲を切り替える。

```bash
LABELS=$(gh issue view "$ISSUE_ID" --json labels -q '.labels[].name')
if echo "$LABELS" | grep -qE '^(survey|docs|spec)$'; then
  export QUALITY_SCOPE=docs
else
  export QUALITY_SCOPE=all
fi

./scripts/quality-check.sh || { echo "品質チェック失敗。停止します。"; exit 1; }
```

#### Step 4-2: 仕様整合性チェック

```
Task(subagent_type="general-purpose", model="$(bash scripts/resolve-model.sh verification)", prompt="
実装が仕様ファイルに適合しているか検証してください。

## 検証項目
1. 検証チェックリストの各項目
2. 状態遷移
3. Fallback ホワイトリスト
4. ファイル構成
5. .spec/invariants.md に反していないか
6. **実験の規律（experiment / validation ラベルの場合）**
   - negative な結論を出しているなら positive/sanity control が PASS しているか
   - baseline を強化しているなら同じ工夫が提案手法にも適用されているか（matched-engineering）
   - 結論に unverified-negative / verified-negative / implementation-bug の格付けがあるか
7. **親 task の goal が書き換えられていないか**

## 出力
各項目を ✅ / ❌ で判定。❌ が1つでもあれば「不合格」と明示。
")
```

**★ negative result を安易に通さないこと**

experiment / validation で negative な結論が出た場合、項目6を満たさない限り
**自動マージせず停止**し、トリアージ未完了である旨を issue にコメントする。

#### Step 5: 完了

```
Skill(skill="issue-finish")
```

コミット、PR 作成、**マージ**、worktree 削除、issue クローズを行う。

**★ issue ごとに必ずマージする。** 複数 issue の変更を溜めてから一括マージしないこと。
溜めると main との乖離が増大し、レビュー不能な規模の PR になる
（`.spec/known-issues.md` KI-D08 と同種の負債）。

#### Step 6: 未確定の再照合

この issue が未確定項目の担当だった場合、**次の issue に進む前に Step 0-2b を実行する。**
同ラベルの担当 issue が複数ある場合は、全てが closed になった時点で実行する。

### Phase Final: task のクローズ判定

全ての子 issue が閉じたら、task の目標が達成されたかを確認する。

```
Task(subagent_type="general-purpose", prompt="
task #${TASK} の目標が達成されたか判定してください。

## 目標の状態
${TASK_GOAL}

## 実施内容
${CHILD_ISSUE_RESULTS}

## 判定
- 達成 / 部分達成 / 未達成
- **goal を書き換えて「達成」にしないこと**
- **goal を小さく読んで「達成」にしないこと**: 「目標の状態」の**成功条件を1項目ずつ照合**する。
  未充足が1つでもあれば「達成」としない。照合できない（成功条件が曖昧）なら停止してユーザーに確認する
- **negative の意味も照合対象に含める**（事前登録の機能が失われるため）
- **未確定節に残る項目を1つずつ照合する**（`解消不能` と記録されたものを含む）。
  成功条件の判定に影響しないことを項目ごとに確認し、**照合できない項目が1つでもあれば閉じない**。
  「解消不能・影響しない」で落とした項目が、そのまま goal を小さく読む経路になる
- **未着手の子 issue を、先行 issue の失敗を理由に落とさないこと**: 落とす提案をする場合、
  その根拠が成功条件に明示されているか確認する。明示が無ければユーザー判断を仰ぐ。
  **判定の基準（auto-reviewer S8 と同じ）: 成功条件から該当項目を原文引用できなければ
  「明示されていない」とみなす。** 引用できない限り落とさない。
  先行と後続が**別の仮説・別の問い**を検証しているなら、先行の失敗は後続の実施可否を左右しない
- experiment が negative だった場合、それは「未達成」ではなく
  「negative という結果が得られた」として扱う。negative の意味は task 作成時に
  事前登録されているので、それと照合すること
")
```

結果を task にコメントし、達成なら閉じる。

**次の task が必要な場合も、ここでは作らない。** 結果駆動の task 生成は `/epic-cycle` が統括する
（投機禁止）。

## Options

| オプション | 説明 |
|-----------|------|
| `--dry-run` | 処理計画のみ表示 |
| `--no-merge` | PR は作るがマージしない |
| `--from <issue>` | 指定した子 issue から再開。**Phase 0 で、既に closed の担当 issue に紐づく未解消項目を Step 0-2b で先に再照合する**（再照合ゲートのバイパスを防ぐ） |

## Related Skills

| スキル | 関係 |
|-------|------|
| `/task-start` | task を作成し、確認のうえ本スキルを呼ぶ |
| `/issue-start` | 各 issue の着手 |
| `/review-spec` | 仕様レビュー（スキップ禁止） |
| `/issue-finish` | 各 issue の完了とマージ |
| `/epic-cycle` | 複数 task を収束まで回す |
