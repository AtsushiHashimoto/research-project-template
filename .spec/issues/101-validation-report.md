# 検証レポート: sync/contribute の非破壊性（V1〜V11）

- **Issue**: #101（task #99 / epic #98）
- **検証対象**: #74・#80 の実装（main マージ済み）
- **仕様**: `.spec/issues/100-sync-reflux-account.md` §2
- **実施日**: 2026-07-31
- **方法**: worktree の複製から模擬テンプレート（SRC）と模擬プロジェクト（PROJ / FLAT）を
  scratchpad に作成し、各 V の PASS 条件を機械判定。実施主体はメインループ
  （検証エージェントがセッション上限で停止したため）

## 判定表

| # | 検証 | 判定 | 観測 |
|---|---|---|---|
| V1 | 固有記述の非破壊 | **PASS** | CLAUDE.md 固有行・rules/ 直下ローカル・.spec 固有節（KI-001）の3点とも sync 前後で sha256 一致 |
| V2 | template/ の完全同期 | **PASS** | 追加（new-rule.md）・変更（doc-principles.md）・削除（optional-features.md）が全て反映。`diff -r` 一致 |
| V3 | .spec 既定節のみ更新 | **PASS** | 既定節がテンプレートと sha 一致、固有節は V1 で不変を確認 |
| V4 | マーカー破損の扱い | **PASS** | `# 既定の` を破損 → exit 1、サマリに `invariants.md` を明示 |
| V5 | contribute の検出 | **PASS** | labels.md の改変が一覧に載り、`--diff` が改変行を含む unified diff を出力 |
| V6 | 旧構造の移行 | **PASS** | #91 フラット模擬で移行モード発動。**削除 8 / 退避 2 / 保持 2** — 一致→削除、改変（MY-FLAT-EDIT）→ `template.bak-*/flat/` 退避、一覧外（my-flat-local.md・テンプレートから削除済みの optional-features.md）→ 保持 |
| V7 | rules/template/ の読み込み | **実行不能→代替PASS** | 新規セッション起動は環境制約で不能。代替静的確認: 11ファイルが再帰的発見の対象パスに配置・全ファイル frontmatter なし（= 無条件読み込み） |
| V8 | 冪等性 | **PASS** | rules+spec の sync 2回目で全ファイルの sha スナップショット一致（変更0） |
| V9 | D3 ガイドの存在 | **PASS** | doc-principles.md に「アカウント層」「個人の好み」の節あり |
| V10 | 還流候補の保全 | **PASS** | template/ の改変（LOCAL-HACK-V5）が `template.bak-*/template/labels.md` に退避され、template/ 本体は新版に復元 |
| V11 | 取得失敗時の無変更 | **PASS** | 無効 `--source` で rules=exit1 / spec=exit1、作業ツリーの sha スナップショット完全一致 |

**結果: 10/11 PASS、1件は環境制約により静的確認で代替。FAIL 0件。**

## 特記事項

1. **V7 の残作業**: canary ルールによる実セッション読み込み確認は、実際の新規セッションで
   `/context` を確認すれば数秒で完了する。次回セッション開始時に人が確認することを推奨
   （template/ 配下のルールが読み込まれていれば、この構成は公式仕様どおり機能している）
2. V6 の「保持 2」には、テンプレート側から**削除された**ファイル（optional-features.md）の
   フラット残存が含まれる。MANIFEST 一覧外となるため「ローカルルール」として保持される。
   厳密には孤児だが、削除は証明できないため保持に倒すのは R3 と整合する安全側の挙動
3. #80 Step 4-2 検証で残った follow-up（template-sync Step 4 の `gh issue create` 直接呼び出し、
   contribute 検出と sync 対象の非対称、install.sh --force 時の cp -r 入れ子）は
   本検証のスコープ外。epic #98 の次 task で扱う
