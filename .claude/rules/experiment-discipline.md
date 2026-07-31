<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## 実験の規律（ネガティブ結論の扱い）

**最初の実験がそのまま正しく動くことはまずない。** negative な結果を見たら、結論を出す前に必ず下記を通すこと。

### 1. まず実装バグ・実験設定ミスを疑う

- **ネガティブ（null/negative）は、まず実装バグ・実験設定ミスを疑う。** 検出力(power)が担保されていない null は「本物の科学的 null」ではなく「テスト/実装が壊れていて何も検出できないだけ」のアーティファクトでありうる。
- **positive/sanity control を必須化**: 「効くはずの状況（planted 効果・手法が効くべき合成タスク）で手法/テストが実際に検出・改善する」ことを先に示す。control が PASS して初めて実タスクの null を信頼する。
- **実装正当性を独立オラクルの test で pin**: matched-compute は params/epochs だけでなく *effective-fit*（train fit が同等か）も確認。loss が実際に適用されているか、masking/sampler 等が正しいかを test で固定し、null が「損失が実は効いていない」等のバグでないことを確認。
- **harness に positive control が無ければ issue 化**して検出力を確認する。

### 2. 比較の公平性を保つ（matched-engineering）

**「negative を疑う」規律を過剰適用すると、逆方向の失敗が起きる。** baseline に提案手法が持たない工夫を投入し、不公平な比較で「提案手法が負けた＝意味がない」と結論してしまう事例が実際に観測されている。

- **matched-engineering**: baseline に加えた工夫は、**提案手法にも同等に適用する**。適用しない場合は理由を明示し、その比較は「提案手法の優位性の検証」ではなく「**baseline の上限測定**」として記録する。
- **baseline 強化の記録義務**: baseline に何を足したかを実験記録に必ず残す。後から比較の妥当性を検証できるようにする。
- **「提案手法が負けた」も negative result である。** 上記1のトリアージ手続きの対象に含める。baseline 側の実装・設定にバグが無いことも同様に確認する。

### 3. 敵対的に検証する

- **レビュー時に敵対的に検証**: negative を見たら「この null はバグ/設定ミスで説明できないか?」を必ず問う。**false-positive と false-negative の両方を疑う**のが規律。
- **最初の原因仮説に飛びつかない**: もっともらしい説明が一度言語化されると、証拠が曖昧でも以降の反復がそれに固着する。原因候補は複数立ててから絞る。

### 4. 結論を格付けする

Issue に記録する際、negative result は必ず以下のいずれかに格付けする。**既定は `unverified-negative`**。

| 格付け | 意味 |
|--------|------|
| `unverified-negative` | 上記1〜3 が未完了。**結論として扱ってはいけない** |
| `verified-negative` | 上記1〜3 を全て通過した negative result |
| `implementation-bug` | 調べたら実装ミス・設定不備だった |

### 由来

- weavenet2 で確立された規律（2026-07-29、同 #1089）をテンプレートへ還流したもの
- 契機は weavenet2 #1077 で「見かけの HARM」が setup 交絡＝false-negative と判明した事例
- 「2. 比較の公平性」は #78 の実態調査で観測された過剰適用の失敗モードへの対処として追加
