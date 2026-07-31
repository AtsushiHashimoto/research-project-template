<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## Worktree データ保護

### 概要

Worktree削除時に重要データ（データセット、実験結果）が失われないよう、データディレクトリを以下のように分離します：

- **`data/shared/`**: 重要データ（全Worktreeで共有、削除時も保護）
- **`data/local/`**: 一時データ（Worktree削除時に一緒に削除）

### データの保存先

**重要データ（保存）:**
```bash
# データセット
mv large_dataset.json data/shared/datasets/

# 実験結果
mv experiment_results.csv data/shared/results/

# 学習済みモデル・ダウンロードモデル
mv best_model.pt data/shared/models/
mv pretrained_weights.pth data/shared/models/
```

**一時データ（削除OK）:**
```bash
# キャッシュ
mv preprocessed_batch.pkl data/local/cache/

# デバッグ出力
mv debug_images/ data/local/debug/
```

### モデル保存の注意事項

**重要**: ダウンロードしたモデル（事前学習モデル、ベースラインモデルなど）は**絶対に `/tmp` に保存しない**。

- ❌ `/tmp/models/` — devcontainer rebuild で消える
- ❌ `~/.cache/` — devcontainer rebuild で消える
- ✅ `data/shared/models/` — 永続化される

```bash
# 正しい例
wget -O data/shared/models/resnet50.pth https://example.com/resnet50.pth

# Pythonでダウンロードする場合も保存先を指定
torch.hub.set_dir("data/shared/models")
```
