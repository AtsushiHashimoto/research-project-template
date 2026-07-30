# 派生プロジェクト実態調査

**実施日**: 2026-07-30
**対象 Issue**: #78
**目的**: #70〜#76 の根拠を、テンプレートのソース読解による推論から、派生プロジェクトの実測に置き換える

---

## 調査の動機

#70〜#76 は当初、**テンプレートリポジトリのソースを読んだ推論のみ**で起票された。このリポジトリはテンプレートであり開発の場ではないため、方法論として誤っていた。実際に以下の誤りが生じた。

| 当初の主張 | 実態 |
|---|---|
| `in-progress` / `out-of-date` / `user-action` / `integrity` は未定義で自動化が壊れている | **派生プロジェクトには実在**。テンプレート側だけを見た誤り |
| far-goal モードはどこにも存在しない | **weavenet2 に実在**（#430 で追加、言及 Issue 72件） |
| negative result のトリアージ規律は未整備 | **weavenet2 の CLAUDE.md に実装済み**（2026-07-29 追加） |

---

## 調査対象

| プロジェクト | Org | 規模 |
|---|---|---|
| **weavenet2** | omron-sinicx | **Issue 579件**（open 102 / closed 477）。主対象 |
| PushVoice | omron-sinicx | skills 31 / agents 9 |
| duo-core | omron-sinicx | skills 27（`review-system-design` を独自保有） |
| internal-rentaro | omron-sinicx | skills 24 |
| TracifyDeviceOfflineCam | BioSkillDX-dev | skills 26 |
| com_bio_vag_visualization | omron-sinicx | skills 26（ラベル未整備） |

---

## 1. ラベル体系の実態（→ #76）

### 1.1 ラベルには2つの独立した出所がある

| 出所 | ラベル |
|---|---|
| **omron-sinicx org 由来**（テンプレート無関係） | `ToDo` `Doing` `Done` `daily-report` `weekly-report` `paper-writing` `tutorial` |
| **本テンプレート由来** | `feature` `bug` `experiment` `validation` `survey` `docs` `refactor` `chore` `blocked` |
| **自動処理制御**（派生側で追加） | `in-progress` `out-of-date` `user-action` `integrity` `review-integrity` `gap-fixed` `qa-pending` `backlog` |

**根拠**: BioSkillDX-dev org の TracifyDeviceOfflineCam のみ、前者7ラベルを持たず GitHub デフォルト（`documentation` `enhancement` `good first issue` 等）を持つ。よって前者は org 単位の設定であり、テンプレートとは無関係。

### 1.2 プロビジョニングが完全にばらついている

| ラベル | weavenet2 | PushVoice | duo-core | internal-rentaro | Tracify | com_bio |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| `in-progress` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `integrity` | ✓ | ✓ | ✓ | ✓ | — | — |
| `out-of-date` | — | ✓ | ✓ | ✓ | — | — |
| `review-integrity` | — | ✓ | ✓ | ✓ | — | — |
| `user-action` | — | ✓ | ✓ | — | — | — |
| `qa-pending` | — | — | ✓ | — | — | — |
| `test` | — | — | ✓ | ✓ | — | — |
| `backlog` / `gap-fixed` | — | — | — | ✓ | — | — |

原因は明確で、**`install.sh` / `setup.sh` / `scripts/*.sh` に `gh label` が1箇所も無い**。ラベルは全て手作業で作られており、必要になった時点で各プロジェクトが個別に追加している。

> **注目**: 最も規模が大きく最も苦戦している weavenet2 に、`out-of-date` `user-action` `review-integrity` が**無い**。`user-action` は「ユーザー対応が必要なため自動処理をスキップする」という安全機構であり、これが機能していない可能性がある。要追加調査。

### 1.3 weavenet2 における使用実績（579 Issue）

| ラベル | 総数 | open |
|---|---:|---:|
| `experiment` | **294** | 62 |
| `in-progress` | 157 | 31 |
| `feature` | 104 | 20 |
| `survey` | 84 | 5 |
| `chore` | 35 | 3 |
| `bug` | 22 | 2 |
| `docs` | 20 | 6 |
| `refactor` | 16 | 2 |
| `wontfix` | 13 | 0 |
| `integrity` | 9 | 0 |
| `blocked` | 8 | 8 |
| `validation` | **7** | 1 |

**使用回数ゼロのラベル（22中10個 = 45%）**:
`Doing` `Done` `ToDo` `daily-report` `weekly-report` `paper-writing` `tutorial` `dependencies` `python` `python:uv`

### 1.4 導かれる結論

1. **`experiment` が全体の51%** を占める。研究プロジェクトの実態は実験駆動であり、#73（negative result 規律）の優先度が最も高い。
2. **`validation` は7件のみ**で `experiment` と役割分離できていない。当初 #76 で挙げた「重複の疑い」は実測で裏付けられた。
3. **org 由来のカンバン系ラベル（`ToDo`/`Doing`/`Done`）は完全に死んでいる。** Issue のラベルではなく GitHub Projects 側で管理されている可能性が高い。
4. **`in-progress` が closed Issue に126件残留**（付与157件中の80%）。`/issue-finish` の削除処理（SKILL.md:16,138）が機能していない。一方 open 102件のうち付与は31件のみで、付与も網羅的でない。**ラベルとして信頼できない状態**。
   - `/issue-scan` は `in_progress` を「対応ブランチが存在」で判定しており（`agents/issue-scanner.md:20`）、**同じ状態が2通りに表現されている**。ブランチ判定に一本化するのが妥当。

---

## 2. far-goal モード（→ #72）

### 2.1 実在する。#72 は「新規設計」ではなく「既存モードの改善」

追加 Issue: **weavenet2 #430**「chore: `/issue-cycle` に online 探索（分解+結果駆動）と far-goal モードを追加」

| ファイル | weavenet2 | テンプレート |
|---|---:|---:|
| `skills/issue-cycle/SKILL.md` | 481行 | 403行 |
| `skills/issue-auto/SKILL.md` | 551行 | 518行 |
| `skills/issue-branch/SKILL.md` | 180行 | 180行（**同一**） |

far-goal に言及する Issue は **72件**。

### 2.2 仕様

**定義**: 1 PR で安全に完了できず、複数段の検証を要する issue（論文再現・大規模実装・経路が結果依存の研究タスク）

**`/issue-auto` の far-goal モード**（SKILL.md 32-48行）:

1. 段プランの確認/作成 — 各段に「独立オラクルで検証するゲート」を必ず定義
2. **次の未完了1段だけ実装** — 段の検証テストを先に書いて green にする。green かつ auto-reviewer 自信度 ≥ 50% でのみ前進
3. **auto-merge せず PR 作成 → `/review` → パスで merge**
4. **残り段がある限り issue をクローズしない** — 最終段のゲート通過で初めてクローズ
5. 自信度 < 50% は停止

**`/issue-cycle` の拡張**: issue 生成源を4種に明示化（gaps / integrity / **分解** / **結果駆動**）、Step 2.6「結果駆動の issue 生成」（投機禁止）、収束条件に「未完了 far-goal 段=0 ∧ 結果駆動=0」を追加、Safety Feature 5「online 探索の発散防止（具体性ゲート）」

**導出元**: #409（Bertsimas BPC 再現）で一発自動実装の忠実・厳密一致確率が **~15-25%** と判明し、auto-reviewer 自信度ゲートで停止。verification-first の段階開発が必要と確認された。

### 2.3 観測された失敗モード

ユーザーからの報告と実測を突き合わせた結果、以下3つが特定された。

#### モードA: novelty 監査が遅く、後から全結果が覆る

**実例**: #898 far-goal 連鎖（段1=#899, 段2=#901, 段2b=#905, 段3=#906, 他 #900/#903/#909/#910）

段階ゲート自体は正常に機能していた:
- 段1: blocking feedback は SEq を安く完全同定できない（構造的ギャップ、certified 0.67@N=20）
- 段2: 構造化市場で単純経験ベイズ prior が残余曖昧性を解消（lift 正、uniform 対照で消失）
- 段2b: lift が N-scaling で拡大（0.35→2.05, N=8→24）→ **W3N 投資を正当化**
- 段3: far-goal 中核ゲート

しかし最終的に **6 Issue すべてが `wontfix`** でクローズ。理由は「探索総括に基づき honest negative でクローズ。**cheap/古典が exact・N=4000 スケール、学習ニッチ無し**」。

**問題は分解プロセスではなく、ゲートの順序**。「古典手法が既に厳密に解けるか」という novelty/baseline 監査は**最初のゲートに置くべき**だったが、6段を消化した後に実施された。

> 注: この連鎖は「far-goal がアホになった例」ではない。段階ゲートは設計どおり機能しており、結論も正しい。問題はゲートの**配置順序**に限定される。

#### モードB: baseline に提案手法に無い工夫を加えて負けさせる

negative を疑う規律（後述 §3）を**過剰適用**した結果、baseline に提案手法が持たない工夫を投入し、不公平な比較で「提案手法が負けた＝意味がない」と結論する。

weavenet2 の CLAUDE.md には **matched-compute**（params/epochs/effective-fit の一致）の規定はあるが、**matched-engineering**（baseline に提案手法が持たない工夫を入れない）の規定が無い。

**#73 の裏返しの失敗モード**であり、#73 の設計時に必ず対で扱う必要がある。「negative を安易に受け入れない」規律だけを強化すると、この失敗モードが悪化する。

#### モードC: 段ごとにマージされず main との乖離が増大

**構造的原因**は `/issue-branch` にある。段の分割に自然に対応する道具でありながら、設計思想が段のマージと矛盾している。

- 「大きなタスクを細かく分割して進めたい場合」（用途 = まさに段）
- 「すべて同じ worktree 内で順次作業し、**各サブタスクごとにコミット＆報告**」（マージが無い）
- 「**worktree 切り替えなし**」

加えて far-goal 仕様の項3（段ごとに PR→review→merge）と項4（残り段がある限りクローズしない）が隣接しているため、**両者が混同され「全段終わるまでマージしない」運用になっている**と見られる。

**実測**:

| 指標 | 値 |
|---|---|
| マージ済み PR の変更行数 中央値 | 368行 |
| 同 最大 | 10,803行 |
| 未マージ PR #630 | **+5,522 / -335、42ファイル、2026-06-17 から放置** |
| 他の長期未マージ PR | #759（617行, 6/25）, #761（403行, 6/25） |

---

## 3. negative result の規律（→ #73）

### 3.1 weavenet2 の CLAUDE.md に既に実装されている

**テンプレートには存在しない章**「### 実験の規律（ネガティブ結論の扱い）」が weavenet2 の `.claude/CLAUDE.md` にある（**2026-07-29 追加**、テンプレート334行に対し362行）。

全文:

> - **ネガティブ（null/negative）は、まず実装バグ・実験設定ミスを疑う。** 検出力(power)が担保されていない null は「本物の科学的 null」ではなく「テスト/実装が壊れていて何も検出できないだけ」のアーティファクトでありうる。
> - **positive/sanity control を必須化**: 「効くはずの状況（planted 効果・手法が効くべき合成タスク）で手法/テストが実際に検出・改善する」ことを先に示す。control が PASS して初めて実タスクの null を信頼する。
> - **実装正当性を独立オラクルの test で pin**: matched-compute は params/epochs だけでなく *effective-fit*（train fit が同等か）も確認。loss が実際に適用されているか、masking/episodic-sampler 等が正しいかを test で固定し、null が「損失が実は効いていない」等のバグでないことを確認。
> - **レビュー時に敵対的に検証**: negative を見たら「この null はバグ/設定ミスで説明できないか?」を必ず問う。false-positive と false-negative の両方を疑うのが規律。
> - **harness に positive control が無ければ issue 化**して検出力を確認する（例: #1087 = drug necessity harness の positive control）。
> - 由来: 2026-07-29 自律 /issue-cycle でのユーザー指示（#1077 で「見かけの HARM」が setup 交絡=false-negative と判明した事例が契機）。

### 3.2 運用されている実例

| Issue | 内容 |
|---|---|
| #1089 | chore: CLAUDE.md に実験規律を明記（上記章の追加そのもの） |
| #1087 | experiment: planted-3way **POSITIVE CONTROL** を追加（negative群の検出力担保） |
| #1077 | 「見かけの HARM」が setup 交絡＝false-negative と判明（規律の契機） |
| #1069 | 実データ necessity 再検証（**negative結論は保留**） |
| #1093 | [bug] 画像生成 axial selection が random と同等＝**実装不良**: 失敗原因を全部洗い出す |

### 3.3 導かれる結論

**#73 は新規設計ではなく weavenet2 からの還流が正しい。** ただしそのまま移植するのではなく、§2.3 モードB（baseline への不公平な工夫投入）への対処を**同時に**組み込む必要がある。片側の規律だけを強化すると逆方向の失敗が悪化する。

---

## 4. エージェント定義とモデル指定（→ #71）

### 4.1 role 分化は既に存在する

PushVoice は agents を **9個**に分化させている（テンプレートは3個）。

| エージェント | 起動条件 |
|---|---|
| `implementer.md` | **`feature` ラベル**の Issue 開始時 |
| `debugger.md` | **`bug` ラベル**の Issue 開始時 |
| `refactorer.md` | **`refactor` ラベル**の Issue 開始時 |
| `reviewer.md` | `/review` スキル実行時 |
| `auto-reviewer.md` | `/issue-auto` の代理判断 |
| `integrity-checker.md` | — |
| `invariants-checker.md` | — |
| `issue-scanner.md` | `/issue-scan` |
| `issue-diff-analyzer.md` | `/issue-diff` |

**ラベル → role の対応付けが既に確立している。** #71 が必要とする role→model マッピングは、この対応表の上に素直に載せられる。設計をゼロから起こす必要はない。

### 4.2 しかし frontmatter は1つも無い

**9個すべてが YAML frontmatter を持たない素の Markdown。** `model:` はもちろん `name:` も `tools:` も無い。

（当初 `---` を検出したが、これは説明文直後の水平線であり frontmatter 区切りではなかった。）

つまり**最も進化した派生プロジェクトでも、エージェントは正式なサブエージェント定義になっていない。** テンプレートと同じ「`subagent_type=general-purpose` で呼び、プロンプト本文に『このファイルの定義に従え』と書く」運用のままである。

**結論**: #71 の中心的指摘（frontmatter が無く `model:` を書く場所が無い）は、テンプレート・派生の双方で成立する。役割分担の設計は派生側から借り、frontmatter 化とモデル割当はテンプレート側で新規に作る必要がある。

---

## 5. auto-reviewer 必読ファイル（→ #79）

`.claude/agents/auto-reviewer.md` が「判断前に必ず読む」と定義する3ファイルの存在状況:

| プロジェクト | `constitution/core-rules.md` | `specs/invariants.md` | `specs/known-issues.md` |
|---|:-:|:-:|:-:|
| weavenet2 | ✗ | ✗ | ✗ |
| PushVoice | ✗ | ✗ | ✗ |
| duo-core | ✗ | ✗ | ✗ |
| internal-rentaro | ✗ | ✗ | ✗ |
| テンプレート | ✗ | ✗ | ✗ |

**全プロジェクトで欠落している。**

これは #79 で「テンプレートの不整合」として起票した内容が、実際には**全派生プロジェクトに及ぶ運用上の欠陥**であることを意味する。

**重大性**: far-goal モードは「auto-reviewer 自信度 ≥ 50% でのみ前進」「< 50% で停止」を中核の安全機構としている（§2.2）。その auto-reviewer が、必読と定義されたコンテキストを**一度も持たないまま**判断を下し続けてきた。§2.3 で観測された失敗モードA・Bと無関係とは考えにくい。

---

## 6. CLAUDE.md の重複（→ #74）

テンプレート（非空行 269行）と各派生プロジェクトの一致率:

| プロジェクト | 非空行 | テンプレート共通 | 固有 | **共通率** |
|---|---:|---:|---:|---:|
| com_bio_vag_visualization | 239 | 197 | 4 | **82%** |
| internal-rentaro | 196 | 150 | 17 | **76%** |
| weavenet2 | 261 | 191 | 29 | **73%** |
| duo-core | 296 | 185 | 68 | **62%** |
| PushVoice | 71 | 3 | 63 | **4%** |

プレースホルダ（`{{PROJECT_NAME}}` 等）は全プロジェクトで置換済み。

**PushVoice を除く4プロジェクトで、CLAUDE.md の 62〜82%（中央値 ~73%）がテンプレートの逐語コピー。** 「プロジェクトごとに CLAUDE.md を持つと重複が多い」という #74 の問題意識は、定量的に裏付けられた。

**PushVoice は例外**で、非空行71行・共通率4% まで削り込まれている。誰かが意図的にスリム化した形跡があり、「何を残せば足りるか」の実例として #74 の設計に有用。

固有部分の内訳（weavenet2 の29行）には「実験の規律」章（§3）が含まれる。**固有部分こそが各プロジェクトで育った価値であり、共通部分の 73% は配り直しコストを生んでいるだけ**という構図が確認できる。

---

## 7. 取り込み時期による交絡 ── 本調査で最も重要な発見

### 7.1 乖離は「独自進化」ではなく「取り込み時期 × ローカル改変量」の関数

各プロジェクトの `.claude/` 導入時期と改変量:

| プロジェクト | 取り込み | 最終変更 | `.claude` 変更数 | template-sync 実施 | **CLAUDE.md 共通率** |
|---|---|---|---:|---:|---:|
| PushVoice | **2025-12-26** | 2026-06-25 | 87 | 7 | **4%** |
| duo-core | 2026-03-17 | 2026-07-05 | 24 | 6 | 62% |
| weavenet2 | 2026-05-26 | 2026-07-29 | 10 | **0** | 73% |
| internal-rentaro | 2026-06-11 | 2026-07-03 | 8 | 1 | 76% |
| com_bio_vag_visualization | **2026-07-28** | 2026-07-28 | 2 | 0 | **82%** |
| TracifyDeviceOfflineCam | 2026-05-07 | 2026-05-07 | 1 | 0 | （実質未使用） |

**取り込みが古く改変が多いほど共通率が低い、という単調相関が完全に成立している。**

これは §6 の解釈を変える。**共通率 73%(中央値) は「本質的に共通な部分」ではなく「まだ乖離していないだけ」である。** 時間が経てば PushVoice のように 4% まで離れる。

したがって #74 の問いは「共通部分をアカウント単位に引き上げる」だけでは足りない。**「なぜ乖離するのか、その乖離は価値ある進化かドリフトか」**を分けて扱う必要がある。

### 7.2 テンプレートは派生プロジェクトより約4ヶ月遅れている

| | 日付 |
|---|---|
| テンプレート本体の最終コミット | **2026-04-08**（`4b16e2c`） |
| weavenet2 に far-goal モードが追加された日 | **2026-06-06**（#430） |
| weavenet2 に「実験の規律」章が追加された日 | **2026-07-29**（#1089） |

**テンプレートは4月から止まっており、その間に派生プロジェクトが独自に前進した。**

### 7.3 還流が機能していない

`git log -S` による検証:

| 派生側で生まれた成果 | テンプレートへの還流 |
|---|---|
| far-goal モード（2026-06-06, weavenet2） | **0件** |
| 実験の規律 / positive control（2026-07-29, weavenet2） | **0件** |
| role 別 agents 9個（PushVoice） | **0件** |
| `review-system-design` スキル（duo-core） | **0件** |

`/template-contribute` スキルは存在するが、テンプレート側の contribute 由来コミットは **2026-04-08 が最後**。

さらに重要なのは、**最も活発で最も苦戦している weavenet2 が template-sync も template-contribute も一度も実施していない**こと。事実上フォークして独立している。

一方 PushVoice は template-sync を **7回**実施しているにもかかわらず共通率 4%。**sync の実施回数と整合性は比例しない。**

### 7.4 構造的な含意

テンプレートは「**生きた共有基盤**」ではなく「**取り込み時点のスナップショット**」として機能している。知見は片方向（テンプレート → プロジェクト、取り込み時のみ）にしか流れず、派生側で育った価値は還流しない。

本調査の出発点そのものがこの構造の産物である。**far-goal の存在に気づけなかったのは、それが weavenet2 のローカル改変として6月に生まれ、テンプレートに還流されなかったから**である。

#70〜#76 の個別課題より、**この還流構造の欠落のほうが上位の問題である可能性が高い。**

### 7.5 副産物: #79 の spec パス問題の根本原因が判明

| 日付 | 出来事 |
|---|---|
| 2026-03-11 | `.claude/spec/` を新設（`feat(workflow): add multi-agent spec review...`） |
| **2026-04-02** | **`b8d8d80` `fix: move spec directory from .claude/spec to .spec`** |

コミット `b8d8d80` は **8ファイル・16挿入/16削除**で全参照を `.spec/` に書き換えたが、**物理ディレクトリ `.claude/spec/issues/.gitkeep` を削除しなかった**。

§ #79 で観測した「参照16箇所 vs 実在ディレクトリ0参照」は、**この不完全な移行の残骸**である。移行漏れであり設計上の対立ではないため、修正は `.claude/spec/` の削除のみで足りる。

---

## 8. 未調査の項目

- [ ] duo-core の `review-system-design` をテンプレートへ還流すべきか
- [ ] worktree の絶対パス問題が各プロジェクトでどう回避されているか（→ #77）
- [ ] weavenet2 で `user-action` `out-of-date` が無いことによる実害の有無
- [ ] PushVoice が CLAUDE.md を 71行まで削って運用できている理由（→ #74 の設計に直結）

---

## 5. 各 Issue への反映事項

| Issue | 反映内容 |
|---|---|
| **#72** | 「新規設計」→「**既存 far-goal モードの改善**」に全面書き換え。改善点はモードA（ゲート順序: novelty 監査を最初に）、モードB（matched-engineering）、モードC（`/issue-branch` と段マージの構造的矛盾） |
| **#73** | 「新規設計」→「**weavenet2 の実験規律の還流**」に書き換え。加えてモードB（過剰適用による不公平 baseline）への対処を必須要件として追加 |
| **#76** | 「未定義ラベル4件の修正」→「**派生側で育った体系の整理とプロビジョニング自動化**」。死んだラベル10個の廃止、`in-progress` のブランチ判定への一本化、`install.sh` への `gh label create` 追加 |
| **#71** | 指摘は成立（派生側も frontmatter ゼロ）。ただし **role 分化はラベル紐付きで既に存在**（PushVoice の implementer/debugger/refactorer）。役割設計は借用し、frontmatter 化と model 割当を新規に作る |
| **#74** | 問題意識を定量的に裏付け。**共通率 62〜82%（中央値 ~73%）**。PushVoice の71行運用が設計の実例になる |
| **#77** | `--relative-paths` の有効性を実証済み（本調査の worktree 作成時に確認） |
| **#79** | 「テンプレートの不整合」→「**全派生プロジェクトに及ぶ運用欠陥**」に格上げ。auto-reviewer 必読3ファイルは5プロジェクト全てで欠落。far-goal の自信度ゲートが無根拠で動作していた |

---

## 付記: 方法論上の教訓

本調査自体でも確証バイアスが生じかけた。`wontfix` の far-goal 連鎖（#898〜#910）を「破綻の実例」という仮説を持って調べたが、中身は健全に機能した段階探索だった。仮説に合わないため、そのまま「失敗例ではない」と記録した。

これは #73 が扱う問題そのものである。**調査対象の失敗モードを、調査者自身が踏みうる。**
