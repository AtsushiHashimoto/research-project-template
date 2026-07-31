<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## 開発ガイドライン

### コード品質
- テストを書いてからコミット
- 新機能にはドキュメントを追加
- リファクタリング時は既存のテストが通ることを確認
- **対症療法的修正の禁止**: 想定される挙動と異なる振る舞いに対して、挙動を上書きする形での修正は保守性を低下させるため禁止。根本原因を特定し修正すること
- **単一情報源の原則（Single Source of Truth）**: 同じ情報を複数箇所で定義しない。修正時に複数箇所を変更する必要がない設計にすること

### 研究ノート
- 実験結果は Issue に記録
- ハイパーパラメータの変更履歴を残す
- データセットのバージョン管理


### ブランチの命名規則
- `feature/ISSUE_ID-description` - 新機能
- `survey/ISSUE_ID-description` - 調査
- `experiment/ISSUE_ID-description` - 実験
- `fix/ISSUE_ID-description` - バグ修正
- `docs/ISSUE_ID-description` - ドキュメント
