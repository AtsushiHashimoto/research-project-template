# Issue #133 自動判断ログ

## メタ情報
- 判断日時: 2026-08-02 16:05
- 自動処理: /task-run（親 task #132）
- 対象仕様: .spec/issues/133-shared-symlink-guard.md（D1〜D3）
- 出自: PR #84（`git diff main pr84 -- scripts/setup-worktree.sh` で原案確認済み）
- 注記: `.spec/` 3ファイルは既定節あり・**プロジェクト固有節は未記入**。既定のみで判断した
  （プロジェクト固有の失敗パターンは捕捉できていない自覚を残す）

## 事前検証（実測した事実）

| # | 事実 | 確認方法 |
|---|------|---------|
| F1 | `data/shared/.gitkeep` は **git 追跡ファイル**。fresh worktree では checkout により `data/shared` が必ず「.gitkeep 入りの実ディレクトリ」として具現化する。**つまり D1 の V2 経路（空ディレクトリ置換）は例外ケースではなく全新規 worktree の標準経路** | `git ls-files data` |
| F2 | `.gitignore` は `data/shared/**` + `!data/shared/.gitkeep`。パス `data/shared` **自体は ignore されない** | `git check-ignore data/shared` → exit 1 |
| F3 | D1 の空ディレクトリ置換を実行すると git status が ` D data/shared/.gitkeep` + `?? data/shared` で**恒久的に汚れる**（sandbox で再現） | scratchpad で git init して再現 |
| F4 | `data/shared` が**実ファイル**の場合、現仕様の表に該当行が無く `ln -sfn` に落ち、**ファイルは黙って削除される**（sandbox で再現。「precious」入りファイルが無警告で消えた） | scratchpad で `ln -sfn` を実行 |
| F5 | `setup-worktree.sh` の呼び出し元は `.claude/skills/worktree-setup/setup.sh`（`exec` の薄いラッパ）**のみ**。`install.sh` / `/worktree-init`（init.sh → init-data.sh）/ `/issue-start` からは呼ばれていない | 全 skills / scripts / install.sh を grep |
| F6 | PR #84 原案には退行が含まれる: 実行ビット 100755→100644、`read -r` の `-r` 削除（shellcheck SC2162）、`/worktree-safe-remove`→`/worktree/safe-remove`（旧スキル表記） | `git diff main pr84` |

## 判断一覧

### 1. D1: 実ディレクトリの検出と分岐

| 項目 | 内容 |
|------|------|
| 質問 | 実ディレクトリ検出の分岐（空→置換 / データあり→exit 1 / 読めない→停止）を導入してよいか。データ喪失経路を塞げているか。exit 1 が初期化フローを壊さないか |
| 判断 | ⚠️ **警告付き許可（下記条件 C1・C2 の仕様反映を必須とする）** |
| 理由 | 方向は正しい。現状の `ln -sf` は R-D01 / KI-D03 型の silent-wrong そのもので、INV-D03（重要データは data/shared に置く＝worktree 削除で消えない）の保証を実質無効化している。「データありなら自動移動せず停止して案内」は握り潰し回避の正しい設計。exit 1 の影響も F5 のとおり呼び出し元は単独スキルのみで、初期化フロー（install / worktree-init）には組み込まれておらず、**停止しても壊れる自動フローは存在しない**。ただし仕様の表には2つの具体的な穴がある（下記） |
| 参照 | R-D01、KI-D03、INV-D03、F1〜F5、`.claude/rules/template/data-protection.md` |
| 自信度（参考記録） | 80% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

**条件 C1（データ喪失経路の残り）**: `data/shared` が**実ファイル**（symlink でもディレクトリでもないが存在する）の場合、D1 の表に該当行が無く `ln -sfn` に落ちて**ファイルが黙って消える**（F4 で実証）。表に「**存在するが symlink でもディレクトリでもない → 停止**」の行を追加すること。壊れた symlink は `-L` が真なので既存の symlink 分岐に入り、削除されるのはリンクのみ（データ喪失なし）→ 追加対応不要。data/shared が別ターゲットを指す symlink も同分岐で非対話時は exit 0 温存（V5 の既存挙動）→ データ喪失なし。

**条件 C2（標準経路で git が恒久的に汚れる）**: F1 のとおり V2 経路は**全新規 worktree で必ず発火**し、F3 のとおり実行後は ` D data/shared/.gitkeep` + `?? data/shared` で git が恒久的に汚れる。エージェントが `.gitkeep` の削除をコミットして main に伝播する退行リスクがあり、親 task goal「退行なく反映」に反する。仕様に .gitignore / 追跡の扱い（例: `.gitignore` を `data/shared`（エントリ自体）に変更し `git rm --cached data/shared/.gitkeep`、物理ファイルは main リポジトリに残す）を明記し、検証項目「**V2 実行後に git status が汚れないこと**」を追加すること。※現行の壊れた挙動（dir 内にリンク生成）は偶然 git-clean だったため、これは新規に顕在化する差分である。

### 2. D2: 旧バージョンが作った stray link の片付け

| 項目 | 内容 |
|------|------|
| 質問 | `data/shared` 内の stray symlink を自動削除してよいか。ユーザーが意図的に作った symlink を誤って消さないか |
| 判断 | ✅ **許可（仕様の文言修正を推奨）** |
| 理由 | (1) 削除対象は **readlink が SHARED_DATA_PATH に厳密一致する symlink のみ**（PR 原案の条件）で、リンク自体を消すだけで**参照先データは消えない**ため、誤検出してもデータ喪失は起きない。(2) data/shared 自体が SHARED_DATA_PATH への symlink になった後、その中に同じ場所を指すリンクは自己参照であり保持価値が無い。(3) パス正規化ずれ（末尾スラッシュ等）で一致しない場合は「データあり」として**停止側に倒れる**ため安全。(4) 空判定より前に実行する順序も正しい。文言修正: 仕様は「`shared` という symlink」とするが、旧バグが作る名前は **`basename $SHARED_DATA_PATH`** であり `shared` 固定ではない。「readlink が SHARED_DATA_PATH に一致する symlink」に修正すること（名前固定だと救済漏れが出る） |
| 参照 | PR #84 原案の stray 判定条件、KI-D03（安全側は停止） |
| 自信度（参考記録） | 90% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 3. D3: メッセージの多言語化

| 項目 | 内容 |
|------|------|
| 質問 | `msg()` に ja / zh / en の新キーを追加してよいか |
| 判断 | ✅ **許可** |
| 理由 | 既存の作法（msg 関数 + case 分岐）に一致。既存パターン優先の原則どおり。**ただし PR #84 原案の混入退行を取り込まないこと**（F6: 実行ビット 100644 化、`read -r` の `-r` 削除、`/worktree/safe-remove` 旧表記）。仕様が「symlink ガード部分のみ抽出」としているのは正しく、V6 がこれを捕捉する |
| 参照 | F6、scripts/setup-worktree.sh 既存の msg() 実装 |
| 自信度（参考記録） | 95% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 4. INV-D03 との関係

| 項目 | 内容 |
|------|------|
| 質問 | この変更は INV-D03 の遵守側か、抵触するか |
| 判断 | ✅ **遵守側（むしろ INV-D03 の実効化）** |
| 理由 | INV-D03 は「重要データは data/shared に置けば worktree 削除でも消えない」という保証。現行バグはこの保証を**黙って**無効化していた（リンクが dir 内に作られ、data/shared への保存物が worktree ローカルに残り削除で消える）。D1〜D2 はこの保証を回復する変更であり、設計判断の変更ではない |
| 参照 | INV-D03、`.claude/rules/template/data-protection.md` |
| 自信度（参考記録） | 95% |
| 停止条件チェック | 該当なし |

### 5. V1〜V7 の十分性

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ **不足あり。以下を追加すること** |
| 追加 V8 | `data/shared` が**実ファイル**の場合 → 停止し、ファイルが削除されないこと（C1 対応） |
| 追加 V9 | V2（空ディレクトリ置換）実行後に **git status が汚れない**こと（C2 対応。` D data/shared/.gitkeep` / `?? data/shared` が出ない） |
| V4 修正 | stray 判定は名前 `shared` 固定でなく「readlink が SHARED_DATA_PATH に一致」で検証（SHARED_DATA_PATH の basename が `shared` 以外のケースを含める） |
| V2 補強 | find の除外リストと削除リストの**一致**を確認（PR 原案は find 側で `._*` を除外するが rm 側に無く、`._foo` のみ残存時に rmdir が失敗して「削除できない」という誤解を招くメッセージで止まる。停止側なのでデータ喪失は無いが、両リストは単一情報源にすること） |

## 停止判断

該当なし。S1: `.spec/` 3ファイルとも存在し既定節あり（プロジェクト固有節は未記入＝記録のみ）。S2: 親 task #132 の goal は確定済み。S3: invariants / ADR への抵触なし（INV-D03 の遵守側）。S4: 検証チェックリストあり・全項目 PASS/FAIL 判定可能（不足分は追加指示で解消可能）。S5: 既存パターン（msg 作法、error/exit 作法）に沿う。S6: experiment ではない（negative 結論の扱いなし）。

## goal 書き換えチェック

なし。仕様は親 task #132「滞留還流の退行なき反映・symlink バグ解消」の範囲内。goal の範囲・成功条件の変更を含まない。むしろ C2 は goal の「退行なく」を守るための条件である。

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] C2 の解法選択（.gitignore 変更 + `git rm --cached`）は main リポジトリの追跡構造を変える。実装 issue で diff を明示し、`/issue-finish` レビューで確認すること
- [ ] 非対話モードで data/shared が別ターゲット指す symlink の場合の exit 0（「cancelled」）は既存挙動として温存（V5）。silent 気味だが本 issue のスコープ外。気になるなら別 issue
- [ ] プロジェクト固有の `.spec/` 節が未記入のため、既定ルールのみで判断している
