# Codex の実行方法

## 開始・再開・圧縮後

1. 作業ディレクトリの git root にある AGENTS.md を読む。`.claude/CLAUDE.md` の `@` は Codex の import 機能ではない。
2. `.spec/core-rules.md`、`.spec/invariants.md`、`.spec/known-issues.md` を読む。欠落・既定節の削除は停止する。
3. `python3 scripts/agent-rules.py --root <git-root>` の各ファイルを順に読む（template → local）。
   読んだファイル名を短く報告する。local の明示的上書きが template の既定に優先する。
4. ファイルを扱う前に同コマンドへ対象パスを渡し、追加の条件付きルールを読む。
   ファイルを扱わない相談は既存の `on-demand.md` の話題から自分で選ぶ。条件を別一覧へ複製しない。
5. session-context フックの出力が無ければ `bash scripts/session-context.sh <issue番号>` を実行する。
   フック出力は参考情報。実装/レビュー前の `bash scripts/read-premises.sh <issue番号>` の失敗は停止する。

## スキル・委譲・モデル

clone / worktree 作成後は `bash scripts/configure-agent-workflow.sh` を実行する。
生成リンクは追跡しない。新しく生成したスキルは次のセッションで `/skills` に表示されることを確認する。

`python3 scripts/agent-skills.py --check --root <git-root>` でリンクを確認する。
Codex の明示呼出は `$<skill-name>` または `/skills`。スキル本文の Claude 用例は
`.claude/rules/template/agent-runtime.md` の操作契約に従って読み替える。
全手順・停止条件・レビュー観点は共有本文が正で、Codex 用の別本文をコピーして作らない。

使える shell、独立エージェント起動、結果待ち、メッセージ、再開のツールを実行前に確認する。
CLI で公開される spawn_agent/send_input/wait 等と、ホスト環境の collaboration.* 等は例で、名前を固定しない。
親→ワーカー→レビューが必要な手順では深さと同時枠も確認する。枠が少なければ独立レビューを順次/小バッチで実行する。
深さや独立性を満たせないときはゲートを省略せず停止し、Issue に不足する能力を記録する。
エージェントを再利用するときは担当・入力・残る文脈を明示し、別観点を独立評価として偽装しない。

モデルは `bash scripts/resolve-model.sh --agent codex <role>` で解決する。
`inherit` はモデル override を渡さずセッションのモデルを継承する意味。Claude の opus/haiku を渡さない。
別モデルを指定する場合は環境が許す fork 形式を使い、指定不能なら黙って別モデルへ置き換えない。
完了した worker と動作中 worker の再開/送信は API の仕様に合わせて区別する。

## 設定と完了

プロジェクトの `.codex/` 設定層の信頼と、`/hooks` での hook 定義の信頼の両方を確認する。

リポジトリの `.codex/hooks.json` は共通処理を呼ぶ登録だけ。初回/変更時は利用者が `/hooks` で信頼状態を確認する。
自動承認・表示・認証は `~/.codex/` の個人設定で、テンプレートや共有スキルから変更しない。
Codex の権限用 auto_review は仕様用 auto-reviewer の代わりにならない。
レビュー・検証・進捗報告を終えて PR を提示する。ユーザーが既に明示承認した範囲では進むが、未承認のマージ/外部送信はしない。
