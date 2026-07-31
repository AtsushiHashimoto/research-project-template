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
