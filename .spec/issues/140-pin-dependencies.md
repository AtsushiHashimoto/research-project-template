# Issue #140 仕様: 依存のバージョン固定（一律ではなく対象ごとに判断）

- 状態: approved（auto-reviewer 判断済み＝警告付き許可。D2a と V12〜V14 を追加。ログ: 140-auto-decisions.md）
- 出自: #64 の項目3 / 親 task #139

## 背景

研究テンプレートの本丸は再現性だが、依存が固定されていない。
**CI が無いぶん価値が上がる** — upstream の破壊的変更に気づくのが
「作業中に rebuild したとき」になるため。

現物（`git grep` で確認）:

| 対象 | 現状 | 場所 |
|---|---|---|
| `torch` | **無指定** | `Dockerfile:87` |
| `@anthropic-ai/claude-code` | **無指定** | `Dockerfile:76` |
| Node.js | `setup_20.x`（メジャーのみ） | `Dockerfile:68` |
| ベースイメージ（CPU） | `python:3.11`（パッチ未固定。実測で **3.11.15**） | `cpu/docker-compose.override.yml:9` |
| ベースイメージ（GPU） | `nvcr.io/nvidia/pytorch:24.12-py3` | `gpu/docker-compose.override.yml:10` |
| devcontainer feature | `docker-outside-of-docker:1`（メジャーのみ） | `cpu/gpu devcontainer.json` |

## ★ この issue の核心は「固定すること」ではなく「対象ごとに判断すること」

親 task の成功条件3は「**一律固定していない** — 対象ごとに固定要否の判断根拠が
記録されている」。つまり **全部固定したら不合格**である。

固定にはコストがある（セキュリティ更新が自動で入らない、更新が手作業になる）。
CI が無いので **自動更新の仕組みも作れない**。手で追える量に絞る必要がある。

## ★ テンプレート特有の論点: 「誰のための固定か」

**本リポジトリはテンプレートであり、成果物は派生プロジェクトである。**
ここで固定した値は `install.sh` 経由で全派生プロジェクトの初期値になる。

| 立場 | 帰結 |
|---|---|
| テンプレートが版を決め打つ | 派生プロジェクトは古い torch から始まる。テンプレート更新が滞ると全体が老朽化 |
| **テンプレートは「固定する仕組み」を配り、値は派生側が決める** | 再現性は各プロジェクトで担保され、テンプレートは陳腐化しない |

**後者を採る。** 具体的には **`ARG` で版を外出しし、`[Project]` として
派生側が書き換える前提であることをコメントで明示する**。
「無指定」から「明示された既定値 ＋ 変更場所が1箇所」に変えることが目的で、
テンプレートが特定の版を強制することが目的ではない。

## 設計

### D1: `torch` — 固定する（`ARG TORCH_VERSION`）

```dockerfile
ARG INSTALL_TORCH_CPU=false
# --- [Project] 実験の再現性に直結するため、プロジェクトごとに版を決めて固定すること ---
ARG TORCH_VERSION=2.13.0
RUN if [ "$INSTALL_TORCH_CPU" = "true" ]; then \
    pip install "torch==${TORCH_VERSION}" --index-url https://download.pytorch.org/whl/cpu; \
fi
```

**理由**: torch の版が変わると**数値が変わりうる**。実験の再現性に直結する。
既定値 `2.13.0` は #141 の実測で実際に入った版（`torch-2.13.0+cpu`）。

**★ `+cpu` ローカル版指定子は付けない。** `torch==2.13.0` は
`--index-url .../whl/cpu` の下では `2.13.0+cpu` に解決される。
`==2.13.0+cpu` と書くと GPU 用インデックスへ切り替えたときに解決不能になり、
**インデックス URL と版指定の2箇所を同時に直す必要が出る**（単一情報源に反する）。

### D2: CPU ベースイメージ — パッチまで固定（digest はやらない）

`python:3.11` → `python:3.11.15`（実測で現在解決される版）。

**digest 固定はしない。** digest まで固定すると、同じパッチ版に対する
**Debian 側のセキュリティ更新（`apt` の再ビルド）も止まる**。
研究環境では過剰で、運用コスト（更新のたびに sha256 を手で貼り替え）に見合わない。

**GPU 側は現状維持。** `24.12-py3` は日付タグで**実質固定済み**。
`latest` 相当ではないので追加の固定は不要。

### D2a: ベースイメージの単一情報源をどちらにするか（auto-reviewer 指摘）

`python:3.11` は**2箇所**に書かれている:

| 場所 | 役割 |
|---|---|
| `Dockerfile:5` の `ARG BASE_IMAGE=python:3.11` | 既定値 |
| `cpu/docker-compose.override.yml:9` | compose からの明示指定 |

**両方を `3.11.15` に書き換えると、同じ版が2箇所に出て V4（単一情報源）に自己矛盾する。**
バージョンを上げるときに片方だけ直る事故が起きる。

→ **compose override 側を正とし、`Dockerfile` の既定値は削除する**（`ARG BASE_IMAGE` のみ）。

- CPU / GPU で**値が違う**以上、正しい所有者は override 側である
- 既定値を消すと `FROM ${BASE_IMAGE}` は**空になってビルドが即座に落ちる**（fail-fast）。
  #141 の F1（空 ARG が `getent` を素通りして**壊れたイメージが完成してしまう**）とは違い、
  ここは**黙って壊れない**ので既定値なしで安全。**この挙動は V12 で実測する**
- 直接 `docker build` する経路（GPU の platform 指定ビルド等）は
  もともと `--build-arg BASE_IMAGE=...` を渡しているので影響しない

### D3: `@anthropic-ai/claude-code` — **固定しない**

**固定しないことを積極的に決める。** 理由:

- **頻繁に更新される。** 古い版に固定すると修正・新機能が入らず、
  レート制限対応やモデル追加といった**実運用に直結する更新を逃す**
- **再現性に寄与しない。** claude-code は実験の数値に影響しない開発ツールである
- テンプレートが版を決め打つと、全派生プロジェクトが**同時に古くなる**

**この判断をコメントとして Dockerfile に残す**（成功条件3の「判断根拠が記録されている」）。

### D4: Node.js — 現状維持（`setup_20.x`）

nodesource の `setup_20.x` は**メジャー固定**。claude-code の実行環境であり、
マイナー/パッチの差で壊れる性質のものではない。
D3 と同じ理由（開発ツールであり数値再現性に無関係）で追加の固定はしない。

### D5: devcontainer feature — **固定しない**（`devcontainer-lock.json` を置かない）

#141 の検証中、`devcontainer up` が `.devcontainer/cpu/devcontainer-lock.json` を
自動生成した（`docker-outside-of-docker` を digest で固定する内容）。
これは **#141 では意図的に削除**し、#140 で判断することにした。

**結論: コミットしない。**

- **CPU 側だけに置くと GPU 側と非対称**になる。両方に置くと同じ digest を2箇所に書くことになり、
  単一情報源の原則に反する（feature は共通なのに設定ファイルが分かれているため）
- feature は開発ハーネス（docker CLI の導入）であり、**実験の数値再現性に無関係**
- lock ファイルは `devcontainer up` が**勝手に再生成する**。
  gitignore しないと毎回 `git status` が汚れ、**偽の還流候補**になる（#122 で同種の問題を経験）

→ **`.gitignore` に `devcontainer-lock.json` を追加**し、生成されても汚れないようにする。
判断根拠は本仕様に残す。

## 変更しないもの（スコープ外）

| 対象 | 理由 |
|---|---|
| `apt-get install` のパッケージ版 | Debian のパッチ更新を止める意味が無い。ベースイメージのパッチ固定で足りる |
| `uv` の版 | 開発ツール。D3 と同じ理由 |
| `curl \| sh` の checksum 検証 | #64 の項目2。**見送りと判断済み** |
| GPU ベースイメージ | 日付タグで実質固定済み（D2） |

## Fallback ホワイトリスト

**なし。** 版指定の失敗（存在しない版）は**ビルドが落ちるべき**であり、
「取れなければ最新で続行」は固定の目的そのものを無効化する。

## 検証チェックリスト

静的:

- [x] V1: `torch` が版指定付きでインストールされる
- [x] V2: CPU ベースイメージがパッチまで固定されている
- [x] V3: `claude-code` を固定しない理由が Dockerfile のコメントに書かれている
- [x] V4: 版を変える場所が**対象ごとに1箇所**（同じ版が2箇所に出てこない）
- [x] V5: `devcontainer-lock.json` が `.gitignore` に入っている

動的（**実測**）:

- [x] V6: CPU の `docker build` が通る
- [x] V7: 入った torch が指定した版である（`torch.__version__`）
- [ ] V8: GPU の `docker build` が通る（**arm64 ホストのためエミュレーション。
  完走しなければ「未検証」と明記する。通ったと書かない**）
- [x] V9: 存在しない `TORCH_VERSION` を渡すとビルドが**落ちる**
  （Fallback が無いことの確認。**negative control**）

ドキュメント:

- [x] V10: `docs/devcontainer-internals.md` の記述が実装と一致
- [x] V11: `quality-check.sh` PASS

### auto-reviewer が追加した検証項目（許可の条件）

- [x] V12: **ベースイメージの版が実ビルド経路で1箇所にしかない。**
  `Dockerfile` の `ARG BASE_IMAGE` に既定値が残って**第2の情報源**になっていないこと。
  あわせて、`--build-arg BASE_IMAGE` を渡さない `docker build` が
  **黙って通らず落ちる**ことを実測する（D2a の fail-fast 前提の確認）。
  **★ 本ホストに buildx が無いため、実測できたのは legacy builder 経路のみ。**
  BuildKit 経路は未測定（エラーは Dockerfile パーサ共通なので同じはずだが、これは推論）
- [x] V13: **固定しない対象すべて**（`claude-code` / Node.js / devcontainer feature / `uv`）に
  判断根拠が記録されている。V3 は `claude-code` だけを見ており、
  goal 条件3の「**対象ごとに**」を満たしきれない
- [x] V14: **GPU イメージの torch が同梱版のまま**であること（**分岐の機構のみ実測**。GPU 実機は未検証）
  （`INSTALL_TORCH_CPU=false` が効いており、CPU 版で上書きされていない）。
  「想定される失敗」表が自ら挙げている失敗モードなのに検証項目が無かった。
  完走しなければ「未検証」と明記する

## 実測の結果

### CPU（すべて実測）

`docker compose ... build` = **EXIT 0**。

| 検証 | 実測値 |
|---|---|
| V7 `torch.__version__` | **`2.13.0+cpu`**（`ARG TORCH_VERSION=2.13.0` が効いている） |
| V2 `python -V` | **`Python 3.11.15`**（パッチ固定が効いている） |
| ログ上の wheel | `torch-2.13.0%2Bcpu-cp311-cp311-manylinux_2_28_aarch64.whl` |

**V9（negative control）**: `--build-arg TORCH_VERSION=99.99.99` でビルド → **EXIT 1**。

```
ERROR: Could not find a version that satisfies the requirement torch==99.99.99
       (from versions: ..., 2.12.1+cpu, 2.13.0+cpu)
ERROR: No matching distribution found for torch==99.99.99
```

**「Fallback を置いていない」ことを、置いていたら落ちなかったはずの入力で確認した。**
固定した版が取れないときに黙って別の版が入る余地が無い。

**V12（fail-fast）**: `--build-arg BASE_IMAGE` を渡さずにビルド →
`base name (${BASE_IMAGE}) should not be blank` で**即座に停止**。
既定値を消しても「壊れたイメージが黙って完成する」ことは無い（D2a の前提が成立）。

`docker compose config` での解決結果:

| 構成 | `BASE_IMAGE` | `INSTALL_TORCH_CPU` |
|---|---|---|
| CPU | `python:3.11.15` | `true` |
| GPU | `nvcr.io/nvidia/pytorch:24.12-py3` | `false` |

`grep -rn "python:3.11" .devcontainer/`（コメント除く）の一致は **1件のみ**（V4 / V12）。

**shellcheck**: 本 issue は `scripts/ensure-gitignore.sh` を変更したため、
ホスト未導入で skip されるのを避け、**ビルドしたイメージ内の shellcheck 0.10.0 で実行**
→ 指摘なし。

### V14: 機構は実測、GPU 実機は未検証

**測ったこと**（CPU ベースイメージで、GPU が通る分岐だけを再現）:

`--build-arg INSTALL_TORCH_CPU=false --build-arg TORCH_VERSION=99.99.99` でビルド
→ **EXIT 0**、`import torch` = `ModuleNotFoundError`。

**存在しない版を渡しても落ちない**＝ D1 で書き換えた `pip install` 行は
`INSTALL_TORCH_CPU=false` のとき**実行されない**。V9（同じ版で `true` なら落ちる）と
対になっており、分岐が両方向で効いていることを示す。

したがって **GPU 側の torch は同梱版のまま**になる。
（#141 の GPU 実測でも `import torch` = `2.6.0a0+df5bbc09d1.nv24.12` を確認済み）

### V8: GPU の `docker build` は**再実行していない**（未検証）

**正直に記録する。通ったとは書かない。**

#141 で同じ Dockerfile の GPU ビルドを amd64 エミュレーションで実測（EXIT 0）しているが、
**#140 の変更後の状態では再実行していない。** 理由:

- #140 が GPU ビルド経路に与える変更は、**実質ゼロ**である
  - `gpu/docker-compose.override.yml` は**コメントの追加のみ**（値は不変）
  - `ARG BASE_IMAGE` の既定値削除は、GPU では compose が明示的に渡すため影響しない
    （`docker compose config` で確認済み）
  - `TORCH_VERSION` は `INSTALL_TORCH_CPU=true` の分岐内にあり、GPU は通らない（V14 で実測）
- 再実行には **33.3GB のイメージ再取得（約40分）＋ エミュレーションビルド（約10分）** が必要

**ただしこれは推論であって測定ではない。** GPU 実機での確認は
**#142（`user-action`）** に含まれる。#139 のクローズ判定ではこの区別を保つこと。

## 検証で見つかった問題と対処（Step 4-2 の敵対的レビュー）

### G1: **V4 を満たしていなかった** — ドキュメントに版を焼き込んでいた

「版が2箇所に出てこない」に `[x]` を付けていたが、実測範囲を
`grep -rn "python:3.11" .devcontainer/` と **`.devcontainer/` に限定**していたため、
`docs/devcontainer-internals.md` の重複を**構造的に検出できていなかった**。

| 値 | 正 | docs の重複 |
|---|---|---|
| torch の版 | `Dockerfile` の `ARG TORCH_VERSION` | 2箇所 |
| CPU ベースイメージ | `cpu/override` | 1箇所 |
| GPU ベースイメージ | `gpu/override` | 2箇所 |

**単なる体裁ではない。** docs は読者に「**プロジェクトごとに版を決めて書き換えてください**」と
指示しており、**その指示に従った瞬間に docs が嘘になる**。
`140-auto-decisions.md` は「さらに `docs/` にも記載がある」と3箇所目を明示していたのに、
実装は2箇所しか解消していなかった。

→ **対処**: docs から版のリテラルを排除し、「**版が書いてある場所（唯一）**」への
参照に置き換えた。あわせて「このドキュメントに具体的な版を書かない」理由を明記。
`gpu/override` のコメント内の重複も一般形（`YY.MM-py3`）に直した。

### G2: 所有者が2種類あることを読者に示していなかった

`BASE_IMAGE` は「compose が正・Dockerfile に既定値を置かない」、
`TORCH_VERSION` は「Dockerfile の既定値が正」。基準は
**CPU / GPU で値が分岐するか**だが、それが読者から見えなかった。

→ docs に「版を変えたいとき、どこを編集するか」の表を追加した。

### G3: feature を固定しない根拠が宣言箇所から見えなかった

根拠は `.gitignore` と docs にあったが、`devcontainer.json` の
`docker-outside-of-docker:1` を読む人には届かない。
→ CPU / GPU 両方の `devcontainer.json` の `features` 直前にコメントを追加。

### G4: `[Project]` マーカーの範囲が曖昧、uv コメントの参照先が誤り

- `--- [Project] ---` の直後に [Template] 側の根拠が9行続き、
  どこまでがプロジェクト所有か読めなかった → **`ARG` の1行だけを挟む**形に変更
- uv のコメントが「#140 **D5**」を参照していたが、D5 は devcontainer feature の判断。
  正しくは「変更しないもの（スコープ外）」表 → 修正

### G5: #140 のクローズ時の注意

GitHub #140 の完了条件には「`docker build` が **CPU / GPU 両方**で通る（**実測**）」がある。
**V8 が未検証である以上、この項目にチェックを入れてはならない。**
GPU 実機分は **#142（`user-action`）** が引き受ける。

## 想定される失敗と切り分け

| 症状 | 疑うもの |
|---|---|
| `No matching distribution for torch==X` | D1 の版指定。`+cpu` を付けていないか（付けると解決不能になりうる） |
| GPU ビルドで torch が上書きされる | `INSTALL_TORCH_CPU=false` が効いているか。GPU 側は同梱版を使う |
| `git status` が毎回汚れる | D5 の `.gitignore` 追加漏れ |
