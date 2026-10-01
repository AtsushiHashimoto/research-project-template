<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## 成果物の保存場所

### survey の成果物

```
docs/surveys/
└── YYYY-MM-DD_topic-name.md
```

### experiment の成果物（3点セット）

```
data/shared/experiments/
└── YYYY-MM-DD_experiment-name/
    ├── data/              # 生データ
    │   └── results.csv
    ├── figures/           # 可視化
    │   └── plot.png
    └── README.md          # 実験内容・結論
```

---

## 進捗報告のルール

- **途中経過は Issue のコメントに Markdown で報告**
  - コードを書いた後、コミット前に進捗を Issue に報告
  - 報告内容：
    - 完了した作業
    - 現在のブロッカー（あれば）
    - 次のステップ

### ★ セッションの区切りと引き継ぎ

1 本のセッションで独立した仕事を続けると、呼び出しのたびに膨らんだ文脈全体を読み直すため費用が増え続ける。
**独立した仕事ごとにセッションを区切る。** エージェントは /clear・/compact を実行できないので、区切りでは次を行う。

- **区切り**: PR をマージした後／関係のない issue に移るとき／長い中断（日をまたぐ等）の前。
- **引き継ぎを issue に書く**: `bash scripts/handoff.sh write <issue番号> <本文ファイル|->`。見出しは
  `### 済んだこと` `### 決まったこと` `### 次の一手` `### 未解決の問い` の 4 つ（該当なしは「なし」。
  欠けるとスクリプトが投稿を拒む）。
  次のセッションがこれだけで再開できるように書く。書き先は続きの作業がある issue（マージ後なら親 task）。
  ユーザーが確定した前提は引き継ぎではなく `premises.md` の置き場所に書く。
- **ユーザーに 1 行で伝える**: 「区切りです。/clear をどうぞ（同じ流れの続きなら /compact）。」
- 次のセッションでは SessionStart フック（`scripts/session-context.sh`）が最新の引き継ぎと epic 前提を読み込む。
  別の issue を続けるときは `bash scripts/session-context.sh <issue番号>`。
- /compact の要約はサブエージェントにも別のセッションにも見えない。残すべきことは要約に頼らず引き継ぎに書く。
