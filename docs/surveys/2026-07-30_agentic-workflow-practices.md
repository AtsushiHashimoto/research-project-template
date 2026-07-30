# エージェント運用ノウハウの文献サーベイ

**実施日**: 2026-07-30
**対象 Issue**: #75
**目的**: #70〜#74 の設計判断を、経験則ではなく一次資料で検証した文献の裏付けをもって行えるようにする

---

## 調査の動機と #78 との関係

本調査は #78（派生プロジェクト実態調査）と対をなす。#78 が**内部の実測**を担当し、本調査が**外部の知見**を担当する。

Issue #75 本文の文献リストは Web 検索による一次スクリーニングの結果であり、Issue 自身が「arXiv ID や主張内容は精読時に必ず一次資料で検証すること。検索結果の要約が不正確な可能性がある」と警告していた。本調査はこの警告の検証から始めた。

**結論を先に書く。警告は半分当たり、半分外れた。**

| 懸念 | 実測結果 |
|---|---|
| arXiv ID が不正確／架空の可能性 | **外れ。20/20 が実在しタイトルも一致**（架空ゼロ） |
| 主張内容が不正確な可能性 | **当たり。8件の誤りを確定**（うち引用の帰属誤り3件） |

**誤りは ID 水準ではなく主張水準に集中していた。** この非対称性そのものが本調査の主要な発見であり、後述の「本サーベイの検証手法の妥当性」で機構的に説明する。

---

## 調査範囲と方法

### 文献の内訳と上限の適用

| 区分 | 件数 | 内容 |
|---|---|---|
| **サーベイ対象（当初）** | 21 | arXiv 20 + Web 1（agentsstandard.com）。Issue #75 本文の記載「26本」は**誤り** |
| **サーベイ対象（追補）** | 4 | カテゴリF（引用ハルシネーション）。Issue 作業項目2「検索の追補」に基づく |
| 小計（上限29本以内） | **25** | auto-reviewer が設定した追補上限（6件）および総数上限（29本）の適用対象 |
| 参照資料 | 5 | サーベイ対象ではなく、**誤った出典の差し替え先**および**出典不明主張の追跡先**として参照したもの |

参照資料5件は `agents.md` / Claude Code 公式ドキュメント / OpenRouter State of AI / Retraction Watch（STAT News は同一分析の報道） / EurekAlert（JMIR 原論文のプレスリリース）。これらは調査対象ではなく訂正の根拠なので上限の対象外として扱った。

### 検証プロトコル

1. **陽性対照**: 各バッチの先頭で `arxiv.org/abs/1706.03762`（Attention Is All You Need）を取得し成功を確認。失敗したら取得系の故障として全結果を破棄。
2. **`curl -L` 必須**: `-L` を省くと arXiv API が 301 を返し、実在確実な陽性対照まで NOT_FOUND になる（実測）。
3. **非実在判定は2チャネル一致を必要条件とする**: 肯定は1チャネルで足りるが、否定は arXiv API と abs ページの両方が否定し、かつ陽性対照が成功した場合のみ。単一チャネルの否定は `検証不能` に留める。実際に `2606.04967` は API が3回連続 `totalResults=0` を返す一方 abs ページは 200 でタイトル一致だった。
4. **arXiv ID を差し替えない**: 取得経路の切替は同一 ID 内（abs → html → pdf）に限る。
5. **逐語引用にはロケータ必須**: `abstract` / `§n` / `Table n` / `vN`。書けない引用は掲載しない。

### 証拠の格付け（5層）

arXiv の `comments` / `journal-ref` / `DOI` 欄で機械的に判定した。判定手順は「`journal-ref`/`DOI` 記入済 → 掲載確定／`comments` に採択記載 → 採択〜投稿中／いずれも空 → 査読情報なし」（[arXiv 公式ガイダンス](https://info.arxiv.org/help/prep.html)）。

| 層 | 定義 | 本数 |
|---|---|---|
| ① | 査読誌・トップ会議採択 | 2 |
| ② | ワークショップ採択（軽量査読） | 2 |
| ③ | プロトコルのみ査読済（Registered Report） | 1 |
| ④ | 非標準の実験的会場 | 1 |
| ⑤ | **査読情報未確認（arXiv メタデータ上）** | 18 |

**⑤は「査読なし」ではない。** 欄が空であることは査読を経ていない証明にならない（未記入・投稿中の可能性）。証拠のない断定は本調査が批判する誤りと同種なので、呼称を「査読情報未確認」とする。

**Issue の作業項目3は「AGENTS.md 標準など査読を経ていないものは格下げ」とするが、格下げ対象は AGENTS.md だけではない。** 当初21本のうち14本（70%）が層⑤で、最優先の C カテゴリ6本中で査読誌掲載は1本のみである。

### 検証範囲の語彙

`検証範囲` 列は4値のみを取る。`abstract v{N}` の行には **abstract に逐語で存在する数値のみ**をロケータ付きで記載し、abstract に無い手法詳細・実験条件・内訳は記載しない。

| 値 | 意味 |
|---|---|
| `全文 v{N}` | 全文取得済み。主張のロケータは節番号まで特定 |
| `abstract v{N}` | abstract のみ。範囲外の主張は採録しない |
| `メタデータのみ` | 実在とタイトルのみ確認 |
| `検証不能` | 取得失敗。**非実在ではない** |

---

## 文献評価サマリー

`存在検証` は全件 ✅（20/20 実在・タイトル一致）のため列を省き、相違があったものだけ備考に記す。

### A. 長期ホライズンタスクの失敗と分解粒度（→ #72）

| 文献 | 層 | 検証範囲 | 主張検証 |
|---|---|---|---|
| [2604.11978](https://arxiv.org/abs/2604.11978) The Long-Horizon Task Mirage? | ⑤ | 全文 v1 | ⚠️ 条件欠落＋**帰属誤り**（下記 誤り4） |
| [2605.15425](https://arxiv.org/abs/2605.15425) Runtime-Structured Task Decomposition | ② | 全文 v1 | ⚠️ 決定的な限定が欠落（正解率は不変） |
| [2605.02572](https://arxiv.org/abs/2605.02572) On Training **Large Language Models** for Long-Horizon Tasks | ① | abstract v1 | ✅（タイトル略記） |
| [2603.19685](https://arxiv.org/abs/2603.19685) A Subgoal-driven Framework | ⑤ | abstract v1 | ✅（寄与の半分が欠落） |
| [2607.05775](https://arxiv.org/abs/2607.05775) Beyond the Leaderboard | ⑤ | abstract v1 | ✅（タイトル略記） |
| [2607.08964](https://arxiv.org/abs/2607.08964) Long-Horizon-Terminal-Bench | ⑤ | abstract **v2** | ✅（副題欠落。到達版は v2） |

### B. モデルルーティング / コスト最適化（→ #71）

| 文献 | 層 | 検証範囲 | 主張検証 |
|---|---|---|---|
| [2604.03527](https://arxiv.org/abs/2604.03527) Explainable Model Routing | ② | 全文 v1 | ⚠️ 条件欠落（手動較正 κ 依存・e2e 評価なし） |
| [2605.06350](https://arxiv.org/abs/2605.06350) Is Escalation Worth It? | ⑤ | 全文 v1 | ⚠️ **否定的結論が欠落**（カスケードは事前ルータに負ける） |
| [2606.27457](https://arxiv.org/abs/2606.27457) Cluster, Route, Escalate | ⑤ | 全文 v1 | ❌ 一部不一致（下記 誤り7） |

### C. 確証バイアス / negative result の扱い（→ #73、Issue が最優先指定）

| 文献 | 層 | 検証範囲 | 主張検証 |
|---|---|---|---|
| [2601.03315](https://arxiv.org/abs/2601.03315) Why LLMs Aren't Scientists Yet | ⑤ | 全文 v1 + PDF v1 | ⚠️ 6失敗モード/4原則は ✅ / **鍵括弧引用は全文に不在**（誤り5） |
| [2604.02485](https://arxiv.org/abs/2604.02485) Failing to Falsify | ⑤ | 全文 v1 | ✅ 条件付き（非thinkingでは混在） |
| [2510.19973](https://arxiv.org/abs/2510.19973) Cognitive Biases in Agentic AI-Driven 6G | ① | 全文 **v4** §I, §III-A1 | ⚠️ 半分誤り（誤り6）。到達版は v4 |
| [2605.16143](https://arxiv.org/abs/2605.16143) Look Before You Leap | ⑤ | 全文 v1 §1–§3.4 | ✅（#73 への関連は弱い） |
| [2604.10696](https://arxiv.org/abs/2604.10696) Camyla | ⑤ | 全文 v1 | ✅ **Issue の重み付けが過小**（誤り8の出典） |
| [2606.24177](https://arxiv.org/abs/2606.24177) Agon（**副題** Built on Prompt Economy） | ⑤ | 全文 v1 | ✅ **誤り5の真の出典** |

### D. コンテキスト管理 / 指示ファイル設計（→ #74）

| 文献 | 層 | 検証範囲 | 主張検証 |
|---|---|---|---|
| [2605.12366](https://arxiv.org/abs/2605.12366) Classifier Context Rot | ⑤ | 全文 v1 | ⚠️ 条件欠落（誤り3）＋緩和策の限定欠落 |
| [2604.08290](https://arxiv.org/abs/2604.08290) Tokalator（**Artificial Intelligence** Coding Assistants） | ⑤ | 全文 v1 | ✅ **Issue の重み付けが過小** |
| [2605.04050](https://arxiv.org/abs/2605.04050) LCM: Lossless Context Management | ⑤ | 全文 v1 | ✅（#74 への直接適用はほぼ無い） |
| [agentsstandard.com](https://agentsstandard.com/) | 二次情報 | 全文（版表記なし、取得日 2026-07-30） | ❌ **不一致**（誤り2） |

### E. Spec駆動開発（→ #70 / #72）

| 文献 | 層 | 検証範囲 | 主張検証 |
|---|---|---|---|
| [2601.03878](https://arxiv.org/abs/2601.03878) Understanding Specification-Driven Code Generation | ③ | 全文 v1 | ✅ ただし **結果が存在しない**（誤り1） |
| [2606.04967](https://arxiv.org/abs/2606.04967) From Prompt to Process | ⑤ | 全文 v1 | ✅（共通脆弱性は3件ではなく**5件**） |

### F. 引用ハルシネーション（追補。本サーベイ自身の検証手法の妥当性に限定して使用）

| 文献 | 層 | 検証範囲 | 主張検証 |
|---|---|---|---|
| [2604.03173](https://arxiv.org/abs/2604.03173) Detecting and Correcting Reference Hallucinations | ⑤ | 全文 v1 | ⚠️ 条件欠落。「79×」は §5.1 から**再現不能**（下限6×のみ整合） |
| [2604.03159](https://arxiv.org/abs/2604.03159) BibTeX Citation Hallucinations（**副題** Evaluation and Mitigation） | ⑤ | 全文 v1 | ⚠️ 3層の定義（post-training-cutoff）が欠落 |
| [2602.05930](https://arxiv.org/abs/2602.05930) Compound Deception in Elite Peer Review | ⑤ | 全文 v1 | ✅ ただし **GPTZero データの二次分析**（一次検出ではない） |
| [2607.00738](https://arxiv.org/abs/2607.00738) Phantom References | ⑤ | 全文 **v2** | ❌ 前段の「2602.05930 と同一内容」は**誤り**（別論文。かつ本論文が 2602.05930 を引用） |

---

## 初期スクリーニングで判明した誤り（8件）

Issue #75 本文の文献リストは**凍結**し、誤りの記録自体を成果物として残す（#78 の先例に倣う）。以下が本文書を正本とする訂正一覧である。

### 誤り1: 文献数と `2601.03878` の性質

- 件数は「26本」ではなく **21本**（arXiv 20 + Web 1）。
- `2601.03878` のメモは「SANER 2026 採択の Stage 1 Registered Report（査読済みプロトコル）」で括弧内は正しいが、**決定的な事実が欠けている**。タイトル自体が *An Empirical Study Design* であり、**Results 節が存在せず、全編未来形、パイロットすら未実施**（§VI「A pilot session (2–3 participants) **will** validate...」）。**さらに対照群がない**（§V「each participant solves one LiveCodeBench problem using **the same** Currante workflow」）。したがって Stage 2 が完了しても「3段階が優れている」は原理的に示せない。目標サンプルサイズ N も本文に記載がない。
- **この論文を「Specification→Tests→Function が有効」の根拠に使うことはできない。**

### 誤り2: `agentsstandard.com` の「nearest-file-wins」— 概念は実在するが帰属先が誤り

実仕様は置換ではなく**連結**である。

> 「**Each tier's file is concatenated into the agent's context — not replaced.**」（`§Loading Model: Scoped Concatenation`）
> 「**Concatenate in order: global → project base → project active → folder**」（`§Resolution Order`）

矛盾時のみ "most specific scope wins conflicts" が適用される副次規則にすぎない。加えて Issue の階層列挙は**5ティアのうち `llms.txt` が欠落**している。

同サイトは個人リポジトリ（`nbiish/agents-standard`）運営で、**バージョン番号・日付・標準化団体・RFC 2119 用語定義のいずれも無く**、アフィリエイト収益リンク（`§Referral Links`）を含む。自己記述も「This standard **proposes**」。**「業界標準として重要」という位置づけは過大であり、二次情報／コミュニティ提案に格下げする。**

**「nearest-file-wins」という概念自体は誤りではなく、出典が違う。** 業界標準の実体は [agents.md](https://agents.md/) である。

> 「AGENTS.md is now **stewarded by the Agentic AI Foundation under the Linux Foundation**.」（`§About`）
> 「used by **over 60k open-source projects**」（`§hero`）
> 「Agents automatically **read the nearest file in the directory tree, so the closest one takes precedence**」（`§4`）／「**The closest AGENTS.md to the edited file wins**」（`§FAQ`）

**ただし差し替えると #74 の論拠は弱くなる。** agents.md は**グローバル（`~/`）ティアを規定していない**（規定はリポジトリ内のネストのみ）。グローバルティアを持つのは格下げ対象の agentsstandard.com 側だけである。#74 の「業界標準の方向と一致」は書き換えが必要（→ #74 への反映事項）。

### 誤り3: `2605.12366` の「2〜30倍」の条件欠落

原文は完全に条件付きである。

> 「Opus 4.6, GPT 5.4, and Gemini 3.1 miss these actions 2× to 30× more often when they occur **after 800K tokens of benign activity** than when they occur **on their own**.」（`abstract v1`）

さらに **2〜30× は見落とし率の比であり絶対値ではない**。絶対値は Opus 4.6 (with thinking) で「recall decreases from 98.6% to 88%」（`§1`）。30× に見えるのはベースラインの見落ちが 1.4% と極小だからで、**低いベースラインの比は倍率が誇張される**。設計根拠には比ではなく絶対 recall を見るべき。

「定期リマインダーで部分緩和」は原文と一致するが、**限定が落ちている**。

> 「this reminder mitigation is **effective across most models for the needle style attacks, but not against the more subtle attacks from MonitorBench** ... **are not a general fix for all types of attacks**」（`§4.6`）

**⚠️ 条件が欠落しているのは Issue #75 本文 D節のみで、Issue #74 本文には「800K トークン以降で 2〜30 倍」と正しく明記されている。#74 の当該記述は訂正対象ではない。**

### 誤り4: `2604.11978` への帰属誤り（#72 に影響）

#72 が `2604.11978` に帰している「失敗はタスク長に非線形に累積。サブタスク単体の高性能は e2e 成功を保証しない」は、**`2607.05775` の abstract の逐語訳**である。

> 「we find that failures compound nonlinearly with task length, that strong performance on individual sub-tasks does not reliably translate into end-to-end success, and that **additional scaffolding does not consistently improve reliability**」（`2607.05775` abstract v1）

前半は `2604.11978` でも独立に支持される（§4「performance degrades non-linearly with increasing 𝐬」）が、**引用元の第3節「追加の scaffolding は信頼性を一貫して改善しない」が #72 の記載から落ちている**。これは #72 の方針（段0 の追加・matched-engineering 規定の追加・ゲートの強化＝いずれも scaffolding の追加）に対する最も直接的な反証である。

加えて `2604.11978` の非線形性は「なだらかな逓減」ではなく**閾値的崩落**であり、崩落点は**ドメイン依存で普遍値が存在しない**（§4「a sharp performance drop beyond small 𝐬」「a transition region on the performance–horizon curve」）。段数や閾値を固定値でハードコードする根拠にはならない。

### 誤り5: `2601.03315` の鍵括弧引用は当該論文に存在しない（#73 に影響）

「最初の実験が negative でも、より確からしい説明は subtle な実装バグ」は、**`2601.03315` の全文（HTML v1・PDF v1 の両方）に存在しない**。`implementation bug` 0件、`more likely` 0件、`subtle` は1件のみ（Appendix A.3、無関係な文脈）。

**真の出典は `2606.24177` §4.6 Motivation Failures / `Premature abandonment.`** である。

> 「A first experiment returns a negative result. The system concludes the idea is infeasible and stops. A human researcher knows that first experiments almost never work—**the more likely explanation is a subtle implementation bug.**」（`2606.24177` v1 §4.6）

なお `2601.03315` の abstract で確認できた6失敗モード（`§3.1`–`§3.6`: Bias on Training Data / Implementation Drift / Memory and Context Issues / Overexcitement and Eureka Instinct / Lack of Sufficient Domain Intelligence / Lack of Scientific Taste）と4設計原則（`§4`: **Start Abstract, Ground Later** / **Verify Everything** / **Plan For Failure and Recovery** / **Log Everything**）は正しい。

**証拠の強さは正直に評価する必要がある。** `2601.03315` は層⑤・**著者2名・n=4 の研究アイデア・各1回の実装ラン**で、著者自身が §6 で「This small sample size prevents robust statistical conclusions about the prevalence of failure modes or the effectiveness of mitigation measures.」と明言している。Issue が「最優先」と指定したことは、この論文の証拠が弱いという事実を変えない。

### 誤り6: `2510.19973` の「確証バイアスの3層」は限定付きで正しい

**論文全体のバイアス侵入層の分類は4つ**であり、3層ではない。

> 「i) **Prompts** are a primary entry point... ii) Biases are deeply embedded in the **training data**... iii) The agent's **reasoning paths**... iv) Biases are also evident in **tool use**, which includes the way memories are stored and retrieved」（`v4 §I`）

つまり**記憶は tool use の下位項目**で独立層ではなく、prompts と training data が Issue の記載から落ちている。一方で「3層」は**確証バイアス固有の増幅連鎖**として確かに存在する。

> 「the agent's **memory retrieval, reasoning/planning and tool use** pipelines each amplify the flawed hypothesis」（`v4 §III-A1`）

**引用は `§III-A1` に限定すれば正しい。** また Issue のリンクは v1 を指すが**現行は v4**。

### 誤り7: `2606.27457` の「コスト予算をハイパーパラメータ化」は用語の取り違え

解釈可能なハイパーパラメータは**予算 B ではなく λ** である。

> 「$\lambda \geq 0$ controls the accuracy-latency trade-off ... making $\lambda$ **directly interpretable as the maximum tolerated error-rate penalty for using the most expensive model**」（`§4.1`）

予算 B は別のユーザ指定値で、`§4.5` Eq.4 が「B を満たす λ を自動選択する」。すなわち「予算のハイパーパラメータ化」ではない。

**さらに Issue #71 本文の記述に誤りがある。** #71 は本論文を「『変数制御＋枠上限時のフォールバック』という本Issueの要件そのもの」とするが、**本論文に枠上限（quota 到達）時のフォールバックは存在しない**。コストは TPOT（デコード速度）であり、回数上限でも金額でもない。

### 誤り8: `feedback convergence` / `premature commitment` の出典

両語の一次出典は **`2604.10696`（Camyla）§3.5** である。

> 「A common failure pattern in LLM-based iterative experimentation is **feedback convergence**: when a trial underperforms, conventional systems generate a single-point diagnosis ... effectively reducing the search tree to a single chain.」
> 「First, **premature commitment**: once a plausible explanation is articulated, subsequent iterations anchor on that explanation even when the evidence is ambiguous.」（いずれも `v1 §3.5`）

`2601.03315` と `2604.02485` には両語とも存在しない。

### 出典を特定できた無出典の定量値（#74）

「2024→2025 で平均プロンプト長が 1.5K→6K トークンと4倍」の出典は [OpenRouter State of AI](https://openrouter.ai/state-of-ai)（Aubakirova et al., 2025-12）である。

> 「**Average prompt tokens per request have increased roughly fourfold from around 1.5K to over 6K**」（`§The Anatomy of Prompt-Completion Shapes`）

**数値は正確だが、#74 の使い方は誤りである。** これは**1リクエストあたりの総プロンプトトークン**（会話履歴・ファイル内容・システムプロンプト・指示ファイルの合計）の平均で、**指示ファイルの長さの推移は一切測っていない**。一次資料が挙げる増加要因は「programming workloads are the dominant driver」であり指示ファイルではない。加えて品質の測定が一切なく、査読文献でもない。**「指示ファイルの肥大は品質の問題」の根拠には使えない。**

---

## 詳細分析

### 1. 分解と scaffolding は効くのか — 本サーベイ最大の対立（→ #72）

**この対立は解消せず、両側を記録する。**

**否定側（#72 が引用していない）**

`2605.15425`（層②、IBM Research）は**固定順序の分解が monolithic より悪化する**ことを実測した。

> 「the static baseline's retry cost (1,632±145 tokens) exceeds the monolithic baseline (904±17 tokens) by **80.5%**, because fixed sequential execution must rerun Subtasks 3, 4, and 5 on failure」（`v1 §3.3`）
> 「confirming that **runtime branching, not decomposition structure alone**, is the primary recovery cost mechanism」（同）

**そして分解は品質を上げていない。正解率は3構成すべて 100% で差がない**（`Table 1` / `Table 2` の `Correct (all runs)`）。改善したのは失敗時のリトライコストのみで、正常実行時のトークンは約3倍になる。`2607.05775` も「additional scaffolding does not consistently improve reliability」（`abstract v1`）と述べる。

**肯定側**

`2603.19685`（層⑤）は推論時のサブゴール分解で「approximately a 10% absolute increase in success rate (SR) on the WebArena-Lite benchmark」（`abstract v1`）を報告。`2605.02572`（層①、ICML 2026）は「horizon reduction is a key principle ... stabilizing training」（`abstract v1`）。ただし後者は**モデルの学習**の話であり、重みを更新しない本テンプレートのワークフロー設計は著者の主張範囲外である。

**整合的な読み方**: 効くのは分解の有無ではなく、**失敗した部分だけを切り離して再実行できるか**である。#72 のモードC（段ごとにマージされず main と乖離）は、まさに切り離せていない側の分解に当たる。**分解と段マージはセットでなければ意味がない。**

### 2. ゲート判定を LLM に委ねられるか（→ #72 / #71）

評価が分かれる。`2604.11978` は**枠を与えれば LLM 判定は使える**ことを示す。

> 40 失敗トレースに対し inter-annotator `κ=0.61`、human–judge `κ=0.84`（`v1 §3.2`）

ただしこれは **7カテゴリの固定タクソノミ＋trajectory grounding を与えた条件下**の数値である。対して `2605.15425` は意図的に LLM を使わない。

> 「**All policies are deterministic conditional logic**, making them auditable, unit-testable, and reproducible.」（`v1 §2`）

**#72 の「auto-reviewer 自信度 ≥ 50% で前進」は両者の中間にあり、どちらの根拠も持っていない。** 構造化タクソノミを与えるか、schema 検証等の決定論的信号に置き換えるかの二択で設計すべき。

さらに **50% が何の確率なのかが未定義である**。`2607.08964` の実測では長ホライズンの e2e 成功率は「**15.2% pass@1** at a partial-reward threshold of 0.95 and **10.9%** at ... 1.0, while the mean pass rate across models is **4.3%** and **1.7%**」（`abstract v2`、46タスク・15モデル）。#72 が内部実測から得た「一発成功 15-25%」と同オーダーで、外部ベンチが独立に裏づけている。**e2e 成功確率が 1.7〜15.2% のレンジにあるなら、「自信度50%」は e2e 成功確率の推定値ではありえず、段単位の局所的確信度としてのみ解釈可能である。**

### 3. 「もっともらしい説明」は関門を通り抜ける（→ #72 / #73）

独立に2件の観測がある。

> `Plausible false attribution`: 「The MCTS reward function was inverted ... The system, asked to explain the poor performance, diagnosed it as "UCB1's exploration preference occasionally finding good moves in failed nodes"—**a coherent-sounding interpretation of a bug it had not detected.** The system did not inspect the reward values.」（`2606.24177` v1 §4.3）
> 「once a plausible explanation is articulated, subsequent iterations anchor on that explanation even when the evidence is ambiguous」（`2604.10696` v1 §3.5）

**したがってトリアージ・プロトコルは「原因を説明させる」形では機能しない。「検証済みの計測値を提示させる」形でなければならない。** これは CLAUDE.md 実験の規律が既に採っている「実装正当性を独立オラクルの test で pin」という書き方が正しい理由の理論的裏付けである。

### 4. 見えない失敗は関門では捕らえられない（→ #72 / #73）

**#73 の前提を提供した論文が、#73 の解決手段の有効範囲を否定している。**

`2606.24177` は失敗を4軸で分類し、`Visibility` を「the most fundamental one」とする。`Premature abandonment`（= #73 の問題設定そのもの）を **Invisible × 修復手段なし**の「沈黙の象限」に置く。

> 「**No adversarial loop can catch an error it cannot see. No protocol can fix a failure whose existence the system has no way to detect.** The failures in this quadrant—anomaly blindness, plausible false attribution, premature abandonment, scientific taste—are **not engineering problems awaiting a better architecture. They are capability problems awaiting better foundation models.**」（`v1 §4.2`）

これは規律を無効化するものではないが、**「関門が効く範囲」と「人間にエスカレートすべき範囲」を明示的に分離すべき**ことを要求する。一方 `2604.10696` は診断の多様化（DDF）が実測で効くことを示す（`§5.1 Table 11`: Full 4/5 wins・平均ΔDice +1.85pp に対し −DDF は 3/5 wins・+1.02pp、n=5）。**両者は「診断の多様化は機構で改善できるが、異常に気づく能力そのものは機構では作れない」と読めば整合する。**

### 5. 反証要求は無料ではない（→ #73）

`2510.19973`（層①、IEEE OJCOMS 採択）は緩和策のコストを明示している。

> 「replacing greedy retrieval with symmetric sampling (Eq. 6) across `q_support` and `q_refute` essentially **doubles the input context and retrieval operations**. Furthermore, computing counterfactual likelihood ratios Λ(x) (Eq. 7) necessitates additional forward passes」（`v4 §III-A1`）

**反証要求を全ての negative に無条件必須化すると、`/review-spec` の並列サブエージェント構成でコストが乗算的に増える。** 同論文は「mandatory **verification gates for high-blast-radius actions**」という段階化を提示しており、**結論の影響範囲に比例させる**設計が妥当である。

### 6. 反証志向の介入は実際に効く（→ #73）

`2604.02485` は本カテゴリで**証拠が最も強い**（11モデル×3条件、80エピソード/条件、統計検定つき、コード公開）。

> 「prompting LLMs with such instruction consistently decreases confirmation bias in LLMs, improving rule discovery rates **from 42% to 56%** on average.」（`abstract v1`）

**ただし2つの重要な限定がある。** ①この 42%/56% は **abstract にのみ現れ、本文・表に再掲も分解もない**（著者による集約値）。②本文は abstract の "consistently" より慎重である。

> 「**Dual-Goal improves task success in eight out of eleven** model–inference scenarios, while **Think-in-Opposites improves task success in all**.」「We found the improvements to be statistically significant for **thinking models**, whereas for non-thinking models the results are **mixed**」（`v1 §4.3`）

**設計上の含意は具体的である。** 採用すべき文言型は「対立仮説を並置させる」（Dual-Goal, 8/11）より「**反対を考えさせる**」（Think-in-Opposites, 11/11）。かつ**効果は thinking モードで有意で、非thinking では Dual-Goal は精度をわずかに下げる**ため、軽量モデル・短い推論で代理判断させる場合は反証プロンプトを足しても効かない、あるいは悪化しうる。

### 7. 事前ルーティング vs 事後エスカレーション（→ #71）

`2605.06350`（B カテゴリで唯一、統計的に堅牢: 5ベンチ×8モデル×50分割）の結論は**カスケードに否定的**である。

> 「A lightweight pre-generation router exceeds the best cascade policy on **four of five datasets**, mainly because it **avoids the cheap model's generation cost** on queries sent directly to a larger model rather than because of a stronger routing signal.」（`abstract` / `§7`）
> 「the full fixed chain has lower normalized gain and lower CR@90 in **every** dataset ... **additional mandatory stages can hurt**」（`§6.2`）

**エージェント文脈ではこの構造的不利がさらに悪化する。** 論文が捨てるのは生成トークン代だけだが、`/issue-auto` の実装が sonnet で走ってから上位に上げる場合、捨てるのは**トークン代＋実行済みのツール呼び出し＋ファイル編集の巻き戻し**である。

**エスカレーション判定の信頼性も低い。** 白箱 log-prob 信号でさえコード・数学ではほぼ無情報である。

> benefit-AUROC: MMLU 0.68 / TriviaQA 0.76 / **MATH 0.55** / **SimpleQA 0.49** / **LiveCodeBench 0.56**（`Appendix B.1 Table 3`）

`2606.27457` は 9,000件の学習データで fine-tune した専用分類器を使うが、それでも **false discovery rate 51%**（`§7.4`）。**3本のいずれも「モデル自身の自己評価」を評価していない**が、より強い信号でこの水準であることは、自己申告に期待する設計の期待値を大きく下げる。

### 8. 指示ファイルの長さと階層化は別問題である（→ #74）

**「長いと悪い」と「階層化すると良い」は独立した命題であり、#74 は両者を1つの流れで論じている。**

まず**階層化は総注入トークンを減らさない**。Claude Code 公式ドキュメントは「**All discovered files are concatenated into context rather than overriding each other.**」と明記し、`@path` import も「**doesn't reduce context, since imported files load at launch**」（[Claude Code memory](https://code.claude.com/docs/en/memory)）。削減する公式手段は `.claude/rules/` の `paths` スコープ化（該当ファイルを扱うときだけ読み込む）と、サブディレクトリの遅延読み込みのみである。

次に**指示ファイル帯域（数千トークン）で「長さ→遵守率低下」を測った文献は本調査の範囲に存在しない**。`2605.12366` は 100K–1M 域、`2605.04050` は「**Below 32K tokens, LCM's deterministic machinery provides no advantage** over Claude Code's native file-system access」（`§4.1`）と、むしろ小規模帯で差が出ないことを示す。**この帯域の唯一の言明は Claude Code 公式ドキュメントである。**

> 「**Size: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence.**」（`§Write effective instructions`）

**これが #74 の「品質の問題でもある」に唯一直接対応する出典である**（ただし根拠データは公開されていない設計ガイダンス）。本テンプレートの `.claude/CLAUDE.md` は実測 **331行**でこの目標を超え、`.claude/rules/` は未使用である。

コスト側の一次根拠は `2604.08290` にある。

> 「A **CLAUDE.md** or `.github/copilot-instructions.md` is **injected silently into every prompt**; a 4,000-token instruction file **incurs the same cost per request as 4,000 tokens of source code**」「**instruction files should be audited before any other optimization**」（`§guidelines`）

**なお `2605.12366` の最も有用な知見は長さではなく書き方だった。**

> 「prompting Opus to start by **outputting a list of the most suspicious actions** before doing its reasoning aids detection **massively with only a small amount of extra tokens used**」「the model fails to identify suspicious actions when asked if any are present, but **when asked to copy suspicious actions it is able to quote them verbatim**」（`v1 §4.3`）

**800K 域の知見を指示ファイル設計に外挿してはならない。** 測っているのは第三者モニターの分類タスクであり、指示遵守（instruction adherence）は一度も測定されていない。劣化の主機序は「lost in the middle」型の位置効果（`§4.4`）だが、指示ファイルは構造上コンテキストの先頭に置かれ、`/compact` 後にディスクから再注入される（公式ドキュメント）ため**最も有利な位置にいる**。ただし同論文のデータセット自体が「80 Claude Code session transcripts ... **5k–1M tokens**」（`§3.4`）である事実は、**セッション全体が容易に 100K〜1M に達する**ことの一次的裏付けであり、問題は「指示ファイルが長い」ではなく「**冒頭に一度与えた指示がセッションが伸びるにつれ相対的に効かなくなる**」という時間軸の問題である。

### 9. 本テンプレートの自己評価（`2606.04967` の6次元）

`2606.04967` は6フレームワーク（GitHub Spec Kit / OpenSpec / BMAD Method / GSD / Spec Kitty / Reversa）を6次元で比較する。**二次情報であり、著者自身が「single rater, without a second independent coder ... we do not report inter-rater reliability」「not as a third-party-validated empirical measurement」、および Reversa が著者自身の作品である利益相反を申告している**（`§2`）。したがって軸として使えるが、採点の権威性は「単著者の主観」水準である。

中心的発見は「**no framework strongly covers all six dimensions**」「The most informative pattern opposes **process depth and portability**」（`§6`）。共通脆弱性は3件ではなく**5件**で、Issue の記載から2件落ちている（`abstract v1`）: specification–code drift / 生成物への過信 / プロセス全体のベンチマーク不足 / **コミュニティ拡張の脆弱性（サプライチェーン）** / **プラットフォーム依存**。落ちた2件は `.claude/skills/` を `install.sh` で配布する本テンプレートに最も直接効く。

以下は**本調査がルーブリック（0=absent, 1=partial, 2=strong）を本リポジトリに適用した自己評価**であり、論文著者による評価ではない。

| 次元 | 評価 | 根拠 |
|---|---|---|
| Specification | **2** | `/review-spec` が状態遷移図・検証チェックリスト・Fallbackホワイトリストまで生成。「抽象化チェック（Aufheben）」は6FWのどれにも無い独自機構 |
| Context | **1** | `.spec/core-rules.md` / `invariants.md` / `known-issues.md` は #79 で**新設されたが中身は「（未記入）」**。宣言された層がまだ空 |
| Roles | **1** | agents は3体すべて「レビュー・分析」ロール。実装は `general-purpose` の汎用エージェントで、**実装者と承認者が同一系統** |
| Execution | **2** | worktree 隔離必須、専用スクリプト群、マージ前スナップショット。Spec Kitty と同型 |
| Validation | **1** | #79 で `quality-check.sh` が構成検出型に修正され `QUALITY_SCOPE=docs` を持つ（本調査で EXIT=0 を確認）。ただし **`survey` 成果物を検証するスキルが1つも存在しない** |
| Portability | **0** | `Task(subagent_type=...)` / `Skill(...)` を SKILL.md 本文に直書き、`gh` 必須。論文の GSD 評価（Port=0「strongly coupled to a specific agent」）と同型 |

合計 **7/12**。参照値: BMAD 10 / Spec Kitty 9 / Spec Kit 8 / OpenSpec 6 / Reversa 6 / GSD 4（`Table 6`）。

**読み取れること3点。**

1. **プロファイルは Spec Kitty に最も近く（Spec=2, Exec=2）、差は Validation と Portability にある。** Spec Kitty が Validation=2 を得た理由は worktree 隔離に加えて「review, **accept and merge**」まで段ごとに閉じているからである（`§5`, `Table 5` dominant strength「Human control points before the merge」）。**本テンプレートは worktree 隔離までは同型だが `/issue-branch` にマージが無い。これは #72 モードC の指摘と完全に一致する。**
2. **論文の中心発見「process depth と portability のトレードオフ」は本テンプレートには当てはまらない。** 既に Portability=0 なので**トレードオフすべき資産が無い**。したがって Roles と Validation の深化を可搬性の犠牲なしに追求できる。
3. **論文が「最も識別力が高い」とした2次元（roles と validation）が、そのまま本テンプレートの2大弱点である。** 逆に識別力が低いとされた specification では 2 を取っており、**`/review-spec` の充実は差別化要因ではない。**

---

## 本サーベイの検証手法の妥当性（カテゴリF）

### 「20/20 実在」は幸運ではないが、安心の根拠にもならない

`2604.03159` の3層のうち、Issue #75 の文献（2026年の論文ばかり）は最下層 **recent (2025–2026, post-training-cutoff)** に完全一致する。この層のフィールド精度は 65.0%、**エントリ全体の正解率は 23.0〜39.3%**（`§4.4`, `Table 8`）。素朴に期待すれば20件全件正解の確率は無視できる値になる。

実際は 20/20 一致した。これが意味するのは一つで、**書誌情報は生成されたのではなく arXiv という権威的ソースに対して決定論的に解決された**ということである。**「20/20」は生成器の性能ではなくリゾルバの性能を測った数字**であり、`2604.03159` の `clibib` / `2604.03173` の `urlhealth` / `2607.00738` の RefChecker がやっていることと同じである。

**しかし検査したのは最も壊れにくい2フィールドだった。** `Table 8` の popular→recent 劣化幅は **Author 17.5pp / Title 19.0pp（最小級）** に対し **Pages 51.8pp / DOI 37.8pp / Year 31.7pp（最大級）**。本調査は ID と Title のみを検査してリスト全体の健全性を推論した。**偏ったサンプリングである。**

### ID は当たったのに主張が外れた機構

`2604.03159` の中心構造と同じ形をしている。

| | `2604.03159` | 本サーベイ |
|---|---|---|
| 属性単位の合格率 | フィールド精度 **83.6%** | ID+タイトル一致 **20/20 = 100%** |
| 単位全体の合格率 | エントリ完全正解 **50.9%** | 主張水準の正しさ **12/20**（誤り8件） |
| 落差 | **32.7pp** | **40pp** |

**高い周辺精度は高い同時精度に合成されない。** ID+著者+タイトルの一致が排除できるのは `wholesale entry substitution`（別論文の取り違え）だけで、`isolated field error` は素通りする（`§4.6`）。そして**本調査の8件の誤りは、そのどちらでもない第3の軸にある — 書誌フィールドは全件無傷である**。

カテゴリFの全論文がこのクラスを測定対象外と明言している。

> 「**Citations that appear correct but subtly misrepresent source content would not be detected.**」（`2602.05930` §4.7）
> 「The measure also makes no claim about ... **whether the cited result is true**」／「Checking an arbitrary technical claim in the body of a paper is **essentially an open problem in automated fact-checking**」（`2607.00738` §3, §1）

**ID 解決は参照の同一性を検証する装置であり、本調査の誤りは主張の帰属の失敗だった。両者は直交する。8件の誤りは文献の予測どおりの帰結であり、「20/20 実在」と矛盾しない。**

### 不都合な含意: 査読による格付けの前提が弱まる

**この節は本サーベイに不都合な結論を含む。隠蔽は確証バイアスなので明記する。**

> 「**Reviewer ratings and acceptance tiers carry essentially no information about whether a paper's bibliography survives verification**, and the rate barely changes between accepted and rejected submissions whose ratings differ by almost two points」（`2607.00738` v2 §5.2）

さらに「we observe likely hallucinated citations even among **award-winning** ones」（同）。`2602.05930` は3〜5名の専門査読を経た 53論文/100件の捏造引用が通過し「**None were caught during review**」「citation checking is not part of the standard reviewer workflow at elite conferences」（`§4.1`）と報告する。

**自己言及的な弱点もある。** カテゴリFの arXiv 4件は**全件が層⑤**であり、格付けを額面通り運用すれば**格付けを否定する証拠が最も割り引かれる**。加えて本調査の当初21本も追補4本もほぼ全て層⑤で、**格付けは実質的に何も弁別していない**。

**ただし弱まるのは主張の一部だけである。** 両論文の測定対象は identity-level failures に限定され（`2607.00738` §3 は「ordinary bibliographic drift」を明示的に除外）、示されたのは「**査読は引用の捏造をフィルタしない**」に限る。「査読は手法の誤りをフィルタしない」は示されていない。査読が主に検査しているのは手法・主張・新規性であって参考文献の実在性ではない、という説明は結果と完全に整合する。

**したがって格付けの解釈を次のように限定する。**

1. 5層は「**手法・主張が独立の専門家に精査されたか**」の代理指標として維持する。「**書誌の健全性**」の代理指標としては**使用禁止**とする。
2. 層⑤を「証拠として弱い」と読み替えない。⑤は取得状況の記述であり質の判定ではない。
3. **格付けを、検証を減らす根拠として引用してはならない。** 本調査では層に関係なく全件に同じ3検査（ID解決／逐語引用のロケータ照合／数値の条件照合）を適用した。層⑤だから厳しく見たのではなく、層に関係なく適用したから8件が見えた。

### 機械的検証を組み込む価値

**費用はほぼ無視できる。** `2607.00738` は「3,703 accepted papers and 221,281 references cost approximately **$157**, or roughly **four cents per paper**」（`§1`）。参照20〜40件なら約 $0.03。ただし「**the dominant cost is not money but the human time needed to adjudicate the raised flags**」（`§6`）。

**しかし効くのは前段調査が想定した装置ではない。**

| 装置 | 文献上の効果 | 本サーベイでの限界利得 |
|---|---|---|
| 同一性・生存性リゾルバ（`urlhealth` 相当） | 非解決URLを 1% 未満に（`2604.03173` §5.1） | **0件**（ID は既に全件通過。8件の誤りを1件も検出しない） |
| **逐語引用のロケータ強制＋文字列照合** | — | **誤り5 は決定論的に検出可能、誤り3・6・7 も原文突き合わせで検出** |

`2607.00738` は主張検証一般を「essentially an open problem」とするが、**ここで必要なのは一般の fact-checking ではない。「鍵括弧で囲った文字列が指定ロケータの本文に存在するか」は grep であって推論ではない。** 開いた問題を解く必要はなく、閉じた特殊ケースだけを機械化すればよい。

**最大の構造的空白は、`survey` 成果物を検証するスキルが1つも存在しないことである。** `/review-spec` は実装前の仕様レビュー、`/review` と `/review-integrity` はコード対象で、CLAUDE.md が `survey` の完了条件を「`docs/surveys/` に結果を残す」と定義しているにもかかわらず**成果物が無検証で完了扱いになる**。

---

## 各 Issue への反映事項

### → #70（Issue作成を /issue-start に一元化）

- `2601.03878` は **結果が存在しない**ため有効性の根拠に使えない（誤り1）。使えるのは「仕様の実体を実行可能なテストスイートにする」という設計原則（`§III`「the test suite itself serves as input specification」）と計測スキーマ（`Table I`）のみ。
- `2606.04967` `Table 4` Specification の問い「*How does intention become a **work contract**?*」は、Issue を単一の型に固定せよという規範であり、**作成専任の唯一の実装を置く方針を支持する**。
- 同 Portability の指標に「local installation」がある。`in-progress` ラベルが新規リポジトリに存在せず `gh issue create` が落ちる問題は**可搬性の欠陥**として扱い、`install.sh` にラベル作成を含めるべき。
- 本調査は「一元化すると欠陥が減る」の定量的根拠を与えない（`2606.04967` は二次情報）。

### → #71（エージェント種別ごとのモデル割当）

- **「まず安いモデルで走らせ、ダメなら上位に上げる」設計を採用しないこと。** `2605.06350` §6.2/§7 の structural-cost 論証はエージェント文脈でさらに悪化する（捨てるのがトークン代に留まらない）。**事前ルーティング方針は支持される。**
- **多段 fallback 列（`["opus","sonnet"]`）は正当化されない。** `§6.2`「additional mandatory stages can hurt」。「枠がある時 fable / 無い時 opus 固定」の2値切替が処方に最も近い。
- **`primary/fallback` 直書きを λ 方式に置き換える案**: `2606.27457` §4.1 の min-max 正規化により λ に「最上位モデルを使うために許容する誤り率ペナルティ」という意味が付き、`§8`「decreasing λ corresponds to increasing model capability」でフォールバック順序が導出できる。**枠が細い週は λ を1つ動かすだけで全 role の割当が整合的に下がる**ため、単一情報源の原則に適う。
- **ただし λ / Error 表の値は本テンプレートでは推定できない**（「Issue×担当モデル×正否ラベル」のコーパスが必要）。形だけ借用して値は人が決めることになり、`2604.03527` の手動較正問題（κ=0.2 なしでは信号が崩壊、`Appendix B.1`）に戻る。**論文からの正しい含意は「複雑さ推定を LLM に自動でやらせるな、ラベル/role で明示せよ」であり、#71 の現案を支持する。**
- **自動エスカレーションを入れないこと。** 9,000件で fine-tune した専用分類器でも FDR 51%（`2606.27457` §7.4）。
- **`2604.03527` §3.4 の決定ログ3要素**（user config / intermediate calculations / final assignments + objective scores）は学習不要で Markdown 宣言的スキルでも実装可能な唯一の主要コンポーネント。
- **Issue 本文の訂正が必要**（誤り7）。`2606.27457` に枠上限時のフォールバックは存在しない。**「Fable 5 の枠上限時にフォールバックが働く」というハード quota への対応は、B カテゴリ3本すべてが扱っていない。この中核要件は文献の裏付けなしで設計する必要がある。**

### → #72（既存 far-goal モードの改善）

- **文献の帰属を訂正すること**（誤り4）。`2604.11978` に帰した一文は `2607.05775` の abstract であり、**引用元の第3節「additional scaffolding does not consistently improve reliability」が落ちている**。#72 の追加はいずれも scaffolding の追加なので、**各追加に「効いたかを測る手段」を付けるべき**（現在 #72 が持っていない要件）。
- **モードC の修正方針が最も強く支持される。** `2605.15425` §3.3 は固定分解が monolithic より 80.5% 悪化することを実測し、改善の主機構は失敗した段だけを再実行できる実行時分岐だと述べる。**段ごとにマージして下流を切り離すことが、分解を有効化する条件である。** `2606.04967` の Spec Kitty 評価（Validation=2 の理由が「review, accept and merge」を段ごとに閉じていること）も同方向。
- **段ゲートの強化**: `2605.15425` §4「a failed subtask's output is **not written to the State Manager** and is never visible to downstream subtasks」→ 「green でない段の成果物を後続段のコンテキストに入れない」まで強めてよい。
- **期待の修正**: 分解は正解率を上げていない（`Table 1`/`Table 2` で3構成すべて 100%）。正常時コストは約3倍。**「分解で品質が上がる」という期待は支持されない。支持されるのは「失敗時の手戻りコストが下がる」だけ。**
- **段数・閾値をハードコードしないこと。** 崩落点はドメイン・モデル依存で普遍値がない（`2604.11978` §4）。
- **自信度50%について**: 「何の確率としての50%か」を先に定義すべき（詳細分析2）。`2607.08964` の外部実測（最強モデルでも完全一致 10.9%、全モデル平均 1.7%）が #72 の内部実測「15-25%」を独立に裏づける。
- **測定項目の候補**（`2606.04967` §7）: specification completeness / consistency between artifacts / rate of human review required / **number of corrections per phase** / stability of decisions / quality of the audit trail。段の中止率・wontfix 率を収束条件に組み込む案が導ける。

### → #73（CLOSED。#87 でマージ済み）

**マージされた CLAUDE.md「実験の規律」節の 由来 は weavenet2 の内部実践と明記されており、誤った文献帰属は含まれていない。** その上で文献が追加できることを記す。

- **格付け3値（`unverified-negative` / `verified-negative` / `implementation-bug`）には先例がある。** `2604.10696` §3.4 は trial outcome status を `baseline` / `success` / `underperforming` / `error` に分け、「**this approach crashed due to a fixable bug**」と「**this approach was correctly implemented but does not improve over the baseline**」を明示的に分離する。**ただし `unverified-negative`（中間状態）に対応する先例は6本のいずれにもない — これは独自貢献である。**
- **「最初の原因仮説に飛びつかない」の一次出典**は `2604.10696` §3.5（`premature commitment`、誤り8）。同節の **DDF はほぼそのまま採用できる**: 単一原因の処方を禁止し、4カテゴリ（アーキテクチャ／ハイパラ／実装バグ／**提案‑実装ギャップ**）にわたる候補を必ず列挙させ、**少なくとも1件は提案‑実装ギャップの監査を必須にする**。
- **`gap audit` は「実装バグと真の negative の切り分け」の最も直接的な機構**。`§3.5`「**Standard execution feedback—which only reports training loss and evaluation metrics—cannot distinguish between "the proposed approach does not work" and "the proposed approach was never actually implemented."**」
- **「敵対的に検証する」の適用範囲を限定すべき**（詳細分析4）。`2606.24177` §4.2 により、関門が効くのは Visible / Partially Visible な失敗まで。`scientific taste` / `anomaly blindness` に属するものは自動判定を禁止して人間に上げる分離が必要。
- **反証要求のコストを明記すべき**（詳細分析5）。blast radius に応じた段階化。
- **プロンプト文言の選択**: Think-in-Opposites（11/11）> Dual-Goal（8/11）。かつ**軽量モデル・短い推論では効かない可能性**（詳細分析6）。
- **`positive/sanity control` の必須化には独立した観測事例がある**: `2601.03315` §3.5「proceeding with hypothesis testing when baseline performance was **95% below established benchmarks**, making any comparative analysis scientifically meaningless」。
- **matched-engineering は文献裏付けなしの独自貢献**として扱うのが正直。「baseline に提案手法が持たない工夫を投入する」を記述した文献は本調査の範囲に見つからなかった（鏡像である `regression to simplicity`＝提案手法を弱める側は `2604.10696` §3.5 にある）。
- **`/review-spec` / `/review` への警告**: `2606.24177` は LLM レビュアが揃って高評価でも人間には即座に不合理な事例（`Fluent nonsense`）を報告している。**レビュアの多数決を合格条件にしないこと。** また `2601.03315` §3.4 は評価が summary/report ファイルに依存すると失敗を見逃すと述べ、**生ログ接地**を要求する。

### → #74（CLAUDE.mdのアカウント単位化と開発ファイル分離）

- **「業界標準の方向と一致」は書き換えが必要**（誤り2）。差し替え後の `agents.md` は**グローバルティアを規定していない**。代わりに**より強い一次根拠がある**: `~/.claude/CLAUDE.md`（User instructions）は Claude Code の**公式にサポートされた第2スコープ**であり、方針1は「業界標準との整合」ではなく「**ツール公式仕様に沿った運用**」として正当化するのが正確。
- **「長いと悪い」と「階層化すると良い」を分離すべき**（詳細分析8）。**階層化は総注入トークンを減らさない。** #74 自身が「別 Issue に分割するか要相談」としている判断を支持する。
- **無出典の定量値「1.5K→6K で4倍」は出典を特定したが、指示ファイル長の話ではない**。設計根拠に使わないこと。代替は `2604.08290` §guidelines（4,200トークンの指示ファイルがセッション予算の5%を占めた実測）と Claude Code 公式の「target under 200 lines ... reduce adherence」。
- **本テンプレートは公式目標を超過している**（`.claude/CLAUDE.md` 331行、目標 200行）。かつ**公式の削減機構 `.claude/rules/` の `paths` スコープ化を一切使っていない** — #74 の完了条件に対して未検討の選択肢が残っている。
- **完了条件「ルール修正時に配り直す必要がない」に直結する公式機能が2つ**: `~/.claude/CLAUDE.md` と、**`.claude/rules/` の symlink 共有**（公式に「you can maintain a shared set of rules and link them into multiple projects」）。後者は26スキル構成の本テンプレートに適合度が高い可能性がある。
- **devcontainer の懸念は実在する**: `~/.claude/CLAUDE.md` はコンテナ内に存在せず、公式緩和策 `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` はマウント前提。project 側からの外部 import は**承認ダイアログが出る**。
- **AGENTS.md 併用の公式解は確定**: `CLAUDE.md` に `@AGENTS.md` を書いて import する（Claude Code は `AGENTS.md` を読まない）。
- **セッション時間軸の対策が有効**（詳細分析8末尾）: `2605.12366` §4.6 の periodic reminder（<3% overhead）と §4.5 の incremental monitoring は、`/issue-report` や `/review-integrity` のような**セッション途中の再確認ステップ**を正当化する。ただし subtle な違反には効かない。
- **方針2（成果物からの開発ファイル分離）には本調査の文献は適用なし。**

### → #76 / #80（ラベル体系・還流フロー）

- `2606.04967` の落ちていた共通脆弱性2件が直接効く。**サプライチェーン**: 「An instruction or skill can lead an agent to execute insecure commands, collect sensitive context or adopt low-quality patterns ... Future frameworks should incorporate **signing, verifiable manifests, permission scoping, provenance review and audit of updates**」（`§6`）。`install.sh` で `.claude/skills/` を配布する本テンプレートの配布経路がこれに該当する。
- **CLAUDE.md 肥大化への反対論拠**: 「**Rule does not mean that we should permanently add the prompt block to the agent prompt; such patches often violate the minimal-prompt principle**」（`2606.24177` §4.1）。恒久追加が常に正解ではない。同節の判定法（「コピペ可能なプロンプトブロックで済むか」）は還流時の検討材料になる。

---

## 限界と未調査

1. **主張水準の誤り率 12/20 は、カテゴリFのどの論文の数値とも比較できない**（誰も測っていない）。比較可能な先行研究として *"Fluency Without Fidelity: Errors in Citation-Attributed Claims in LLM-Generated Literature Reviews in Mental Health"*（*J Technol Behav Sci*, DOI 10.1007/s41347-026-00630-6）を同定したが、**追補上限と1ホップ制約により未取得**。次回サーベイの最優先候補。
2. **Tier2 の6本は abstract 止まり**（`2605.02572` / `2603.19685` / `2607.05775` / `2607.08964`、および `2605.16143` は §1–§3.4、`2510.19973` は §I/§III-A1 のみ）。abstract に載らない実験条件・内訳は取り逃している。
3. **一次資料に到達できなかったもの**: *The Lancet* correspondence（"Fabricated citations: an audit across 2·5 million biomedical papers"）は **HTTP 403 で `検証不能`**。関連数値（2.5M論文／97.1M参照／4,046件／2,810論文）は**すべて二次報道由来**であり一次確認済みとして扱ってはならない。JMIR 原論文（Linardon et al. 2025;12:e80371）も全文未取得で、19.9% / 45.4% はプレスリリース本文からの引用。
4. **`2604.03173` の「79×」は §5.1 から再現不能**（算出可能な最大は約61×）。下限6×のみ整合。**引用しないこと。**
5. **`2605.04050` の ID と投稿日の不整合は未解決**: ID の `2605` は 2026年5月を示すが `published` は **2026-02-14**。ID は差し替えていない。原因は特定できず推測しない。
6. **ソフトウェア開発の多段実装タスクを直接評価した文献は `2605.15425`（2ワークロード・gpt-4・10 run）と `2607.08964`（46タスク）のみ。** `2604.11978` は §1 で「debugging multi-file software systems」を動機に挙げるが評価ドメインに含まない。**#72 が扱う「複数日にわたる研究タスクの多段実装」を直接評価した文献は1本もない。**
7. **利益相反のある文献2件**: `2605.04050`（自社エージェント Volt が Claude Code に勝つと主張。著者自身がベンチ汚染を自認し「the gap **narrows**」と述べる）、`2606.04967`（Reversa が著者自身の作品）。
8. **未調査の候補（次回への申し送り）**: 上記1のほか、GPTZero の元レポート（`2602.05930` のデータ源）、`2606.04967` の traction スナップショット（リンクが本文に無く到達経路なし）、`2601.03878` の Stage 2（未公表）。

---

## 付記: 方法論上の教訓

**誤りの伝播経路は3段で、毎回失われるのは「条件」だった。**

一次資料 → Web 検索要約（または他論文からの孫引き）→ Issue 本文。この過程で数値そのものはむしろ正確に伝わっており、**壊れるのは条件節である**（800K という閾値、「総プロンプト長であって指示ファイル長ではない」、「連結が原則で nearest-wins は矛盾時のみ」、「正解率は変わっていない」、「結果はまだ存在しない」）。

**そして引用の帰属は、条件よりさらに壊れやすい。** 8件の誤りのうち3件（誤り4・5・8）は帰属誤りで、いずれも**主張自体は文献の中に実在する**。もっともらしい論文に、もっともらしい主張が結び付けられていた。`2602.05930` の分類でいう `Semantic Hallucination`（primary 1% だが **secondary 63%**）に相当し、同論文が「63% of fabrications pass this check」と述べる通り**目視の妥当性チェックでは検出できない**。

**したがって「一次資料で検証する」は「ID を確認する」では足りない。** 本調査で実際に効いたのは、鍵括弧の逐語引用にロケータを強制し、原文に文字列が存在するかを照合する手続きだった。ID 解決は0件、ロケータ照合は3件を捕らえた。

**最後に、本調査自身が確証バイアスを犯す誘因があったことを記録する。** `2602.05930` を「機械的検証は必要だ」という結論の支持証拠としてだけ引き、同じ論文の「複合的欺瞞は複数の検証ヒューリスティクスを同時に突破する」が**本調査のヒューリスティクスも同様に突破する**という含意を省く誘因があった。`2607.00738` の「acceptance tiers carry essentially no information」も、格付けを採用済みの本調査に不都合だから弱く紹介する誘因があった。両方とも本文に明記した。

---

**関連**: #78（内部実測。矛盾時は事実記述は #78 優先、機構説明は本調査優先、設計判断は両方併記）／ #79（本調査中に `QUALITY_SCOPE=docs` の動作を確認）
