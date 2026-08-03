# Issue #141 仕様: コンテナの主プロセスを非 root にする（USER / WORKDIR）

- 状態: approved（auto-reviewer 判断済み＝警告付き許可。V16〜V18 を追加。ログ: 141-auto-decisions.md）
- 出自: #64 の項目4 / 親 task #139

## 背景

`.devcontainer/Dockerfile` に `USER` 指示が無く、**コンテナの主プロセスが root** で動く。
`devcontainer.json` の `remoteUser: vscode` は VS Code 経由のシェルにしか効かないため、
`docker compose run` / `docker exec` を直接叩くと root になり、
**root 所有のファイルが `/workspace`（＝ホストのリポジトリ）に残る**。

Linux ホストや共同研究者の環境では、その後の `git` 操作やファイル削除が
権限エラーで止まる。macOS の Docker Desktop は UID を写像するため症状が出にくく、
**テンプレート開発環境では見えない失敗モード**である（#135 と同型）。

## 既知の障害: uv が root 専用パスにある

```dockerfile
# Dockerfile:50-52（現状）
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"
```

インストーラを root で走らせているため uv は `/root/.local/bin` に入る。
`USER vscode` を足すだけでは **`/root` が非 root から読めず uv が消える**。
「USER を1行足すだけ」と見積もると必ず踏む。

## 設計

### D1: uv をシステム共有パスに入れる（PATH 追記をやめる）

```dockerfile
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh
```

**PATH を書き換えずに解決する。** `/usr/local/bin` は既定 PATH に含まれるため、
`ENV PATH="/root/.local/bin:${PATH}"` の行を**削除できる**。

**★ 実測で確認済み**（`python:3.11-slim`、本 issue 着手時）:

| 確認項目 | 結果 |
|---|---|
| インストール先 | `/usr/local/bin/uv`, `/usr/local/bin/uvx` |
| `/root/.local/bin` の残骸 | **無し**（ディレクトリごと作られない） |
| 非 root（`nobody`）からの実行 | `uv 0.12.1` — **PATH 設定なしで成功** |

`INSTALLER_NO_MODIFY_PATH=1` は、インストーラが `~/.bashrc` 等へ PATH 追記するのを止める。
システムパスに入れる以上その追記は不要で、**root のホームに副作用を残さない**ため付ける。

**代替案を採らない理由**: 「`/root/.local/bin` に入れてから `/usr/local/bin` へ symlink」は、
インストール先と参照先が2箇所になり、uv 更新時に片方だけ変わりうる（単一情報源の原則に反する）。

### D2: ビルドは root、最終 USER のみ非 root

`apt-get` / `npm install -g` / `pip install` は root が必要なので、**ビルド段階は root のまま**。
Dockerfile の**末尾**で切り替える。

```dockerfile
WORKDIR /workspace
USER $USERNAME
```

`USERNAME` は既に `ARG USERNAME=vscode`（Dockerfile:25）で定義済みで、
同一ステージの後続命令から参照できる。**ユーザー名を2箇所に書かない。**

### D3: `NOPASSWD` は残す

`post-create.sh` は sudo に6箇所依存する（`chown` / `tee /etc/machine-id` /
`sed -i /etc/bash.bashrc` / `npm i -g` / `ln -sf /usr/local/bin` / `tee /etc/profile.d`）。
#64 の判断で `NOPASSWD:ALL` は残すため、これらは**そのまま動く**。

### D4: features は影響を受けない

`docker-outside-of-docker` 等の devcontainer features は、devcontainer CLI が
Dockerfile の**後段**に `USER root` を挟んで導入し、その後 `containerUser` に戻す。
本変更で feature のインストールが壊れることはない。

## 変更しないもの（スコープ外）

| 対象 | 理由 |
|---|---|
| `NOPASSWD:ALL` | #64 の項目1。**見送りと判断済み**（コメントに根拠を記録） |
| `curl \| sh` の checksum 検証 | #64 の項目2。見送りと判断済み |
| `ENV PATH="/usr/bin:${PATH}"`（Dockerfile:60） | Node.js 優先のための既存設定。本 issue と無関係 |
| `docker-outside-of-docker` feature | 無効化はセキュリティ方針の変更であり、親 task の goal 外 |

## Fallback ホワイトリスト

**なし。** 本 issue に条件分岐フォールバックを導入しない。
`USER` の切り替えは成功/失敗が二値であり、「駄目なら root で続行」は
**目的そのものを無効化する**ため許可しない。

## 検証チェックリスト

静的（コード確認）:

- [x] V1: Dockerfile の最終 `USER` が `$USERNAME`（非 root）である
- [x] V2: `WORKDIR /workspace` がある
- [x] V3: `ENV PATH="/root/.local/bin:${PATH}"` が**削除**されている
- [x] V4: uv のインストール先指定が1箇所だけ（symlink 等の二重管理が無い）

動的（**CPU イメージで実測**。`docker build` ＋ `docker run`）:

`docker compose ... build` = **EXIT 0**（`torch-2.13.0+cpu` を導入、Dockerfile の全17ステップ完走。
compose は末尾に `LABEL com.docker.compose.image.builder` を1つ足すのでログ上は18と表示される）。

- [x] V5: `id -u` = **502**、`whoami` = `vscode`（root でない）
- [x] V6: `pwd` = `/workspace`
- [x] V7: `uv --version` = `uv 0.12.1`、`command -v uv` = `/usr/local/bin/uv`
- [x] V8: `claude --version` = `2.1.197 (Claude Code)`
- [x] V9: `gh --version` = `gh version 2.97.0`
- [x] V10: `sudo -n true` 成功
- [x] V11: `python -c "import torch"` = `2.13.0+cpu`
- [x] 追加: `echo $PATH` に `/root/.local` を含まない（D1 の残骸が無いことの確認）

GPU イメージ:

- [x] V12: GPU ベースイメージでも同じ検証が通る（**一部未検証あり**。下記「V12 の結果」を参照）

**★ V12 の実行可能性**: 本ホストは `linux/arm64`、GPU ベースイメージ
`nvcr.io/nvidia/pytorch:24.12-py3` は `linux/amd64` のみ。エミュレーションで試行するが、
**完走しない場合は「未検証」と明記して user-action に回す。**
`docker build が通った` と**書かない**。実行していない検証を通過扱いにしない。

ドキュメント:

- [x] V13: `docs/devcontainer-internals.md` が実装と一致（Step 4-2 の指摘3件を反映後）
- [x] V14: `docs/security.md` の `sudo NOPASSWD` / コンテナ隔離の記述が実装と一致
  （Step 4-2 で**誤記2件**を指摘され修正。下記 F4 参照）

- [x] V15: `quality-check.sh` PASS（実行4件 / 未実行3件。shellcheck はホスト未導入・本 issue は
  シェルスクリプトを変更していない）

### auto-reviewer が追加した検証項目（許可の条件）

- [x] V16: **`docker compose run` 経路**で `id -u` ≠ 0。
  V5〜V11 は素の `docker run` だが、**背景に書いた実際の障害経路は compose 直叩き**である。
  entrypoint（GPU の NVIDIA entrypoint 含む）を通る経路を測っていないと、
  「直したはずの経路」を検証していないことになる
- [ ] V17: bind mount した `/workspace` にコンテナからファイルを作り、
  **ホスト側から見た所有者が root でない**ことを確認する。
  goal 条件4の後半「`/workspace` に root 所有ファイルが残らない」の**直接測定**。
  **★ macOS の Docker Desktop は UID を写像するため、ここは偽陰性になりうる**
  （root で作っても host 側でホストユーザー所有に見える）。
  その場合は「この環境では判定不能」と記録し、PASS と書かない
- [x] V18: **`devcontainer up`（CPU）が完走する**。
  features の導入、`updateRemoteUserUID`、`postCreateCommand`（sudo 6箇所）、
  `postStartCommand` を含む end-to-end 確認。goal 条件5の CPU 側に対応する

## 実測の結果

### V12（GPU）の結果: **ビルドと非 root 起動は実測 PASS。GPU デバイス接続は未検証**

`nvcr.io/nvidia/pytorch:24.12-py3`（amd64、33.3GB）を `--platform linux/amd64` で取得し、
エミュレーションでビルド・実行した。**当初の見込み（完走しないかもしれない）に反して完走した。**

`docker build --platform linux/amd64 ... = EXIT 0`（全17ステップ）。実行結果:

| 確認 | 結果 |
|---|---|
| `id -u` / `whoami` | **1000** / `vscode` |
| `pwd` | `/workspace` |
| `command -v uv` | `/usr/local/bin/uv` — `uv 0.12.1 (x86_64-unknown-linux-gnu)` |
| `claude --version` | `2.1.197` |
| `gh --version` | `2.97.0` |
| `sudo -n true` | 成功 |
| `import torch` | `2.6.0a0+df5bbc09d1.nv24.12`（ベースイメージ同梱版のまま） |
| PATH に `/root/.local` | 含まれない |

**最大のリスクだった「NVIDIA entrypoint が root 前提ではないか」は否定された。**
`/opt/nvidia/nvidia_entrypoint.sh` は非 root で正常に動作する。

**★ 未検証（正直に記録する）**:

- **GPU デバイスへの実接続（`nvidia-smi`）は検証していない。** 本ホストに NVIDIA GPU が無い
  （起動時に `WARNING: The NVIDIA Driver was not detected` が出る）。
  これは環境の制約であり、本変更の成否とは独立
- **`compose` 経由の GPU ビルドは通らなかった。** ただし原因は本変更と無関係で、
  ホストの docker に **buildx が入っておらず legacy builder が `--platform` を扱えない**ため
  （`NotFound: content digest ... not found`）。`docker build --platform` を直接叩くと通る。
  実 GPU ホスト（amd64）では platform 指定自体が不要なので、この失敗は再現しない
- GPU 側の `devcontainer up`（features 込みの end-to-end）は未実行

### V17 は **この環境では判定不能**（PASS と書かない）

`docker compose run` でコンテナ内から `/workspace/data/local/` にファイルを作り、
ホスト側から所有者を見た結果:

| コンテナ内のユーザー | コンテナから見た所有者 | **ホストから見た所有者** |
|---|---|---|
| `vscode`（uid 502） | `502 20` | `502 20` |
| **`root`（uid 0）— 対照実験** | `0 0` | **`502 20`** |

**root で作ったファイルもホストからはホストユーザー所有に見える。**
macOS Docker Desktop（VirtioFS）が UID を写像するためで、
**この測定には検出力が無い**（変更前でも同じ結果になる）。

対照実験を置かずに上段だけを見れば「非 root 化できた証拠」に見えたはずで、
これは `experiment-discipline.md` の言う「positive/sanity control が無い null」と同型です。
**検出力の無いテストを PASS と書かない。**

goal 条件4の後半「`/workspace` に root 所有ファイルが残らない」は、
**Linux ホストでのみ判定可能**です（bind mount が UID をそのまま通すため）。
そちらは user-action として残します。

### V18 の実測内容（`devcontainer up`、CPU）

`{"outcome":"success", "remoteUser":"vscode", "remoteWorkspaceFolder":"/workspace"}`。
起動後のコンテナ内で確認:

| 確認 | 結果 |
|---|---|
| `id` | `uid=502(vscode) gid=20(dialout) groups=20(dialout),**991(docker)**` |
| `pwd` | `/workspace` |
| `uv` | `/usr/local/bin/uv` — `uv 0.12.1` |
| `sudo -n id -u` | `0`（post-create.sh の sudo 6箇所が動く） |
| `docker --version`（feature） | `29.7.1` — **feature の導入は壊れていない**（D4 の確認） |
| `/home/vscode/.claude` の所有者 | `vscode`（named volume ＋ post-create の chown が機能） |
| `.bashrc` の `claude-skip-permissions` | 1 件（post-start.sh が機能） |

**★ 副次的に判明した事実（#64 の訂正の裏付け）**: 非 root ユーザーが
**`docker` グループ（991）に入っています**。`docker-outside-of-docker` feature が
そう設定するためで、**sudo 無しでホストの Docker socket に到達できます**。
「NOPASSWD を消せばホスト脱出を塞げる」が成立しないことの実測証拠であり、
#64 に投稿した訂正コメントの内容と一致します。

### auto-reviewer からの申し送り

- **D4（features が無事）は D3（NOPASSWD 維持）に依存する。**
  `docker-outside-of-docker` は非 root 時に socket の権限調整で sudo を使う。
  本 issue では両方維持するので実害は無いが、**将来 NOPASSWD を外すときは
  この依存を先に解消すること**（#64 の再検討条件に連動）
- `uv self update` は `/usr/local/bin` への書き込みになるため非 root では失敗する。
  `sudo uv self update` で回避可能。実運用上の影響は小さいが既知の副作用として記録する
- 本判断は **#139 のクローズ承認ではない。** goal 条件5（GPU 起動）は
  task のクローズ判定時に S7 で改めて照合すること

## 想定される失敗と切り分け

| 症状 | 疑うもの |
|---|---|
| `uv: command not found` | D1 の PATH。`/root/.local/bin` の ENV が残っていないか |
| GPU で起動しない | NVIDIA entrypoint が root 前提。**負の結果として記録**し root 前提の結合を報告 |
| `/workspace` に書けない | ホスト側 UID と `USER_UID` の不一致（下記 F2） |
| `unable to find user vscode` | `USER_UID` / `USER_GID` が空のままビルドされた（下記 F1） |

## 検証で見つかった問題と対処（Step 4-2 の敵対的レビュー）

### F1: `ARG USER_UID` に既定値が無く、**本 issue が起動不能の退行を持ち込んでいた**

`Dockerfile:26-27` は `ARG USER_UID` / `ARG USER_GID` を**既定値なし**で宣言していた。
build-arg を渡さずにビルドすると `getent group`（引数なし）が exit 0 を返すため、
**vscode ユーザーが作られないままビルドが成功する。**

変更前は `USER` 行が無かったので root で普通に起動していた（症状が出なかった）。
`USER $USERNAME` を足したことで、この経路のイメージは
**起動時に必ず `unable to find user vscode` で落ちる**ようになった。

compose 経由なら `USER_UID: ${UID:-1000}` が渡るので踏まないが、
**V12 の GPU 検証では `docker build --platform` を直接叩いており、現にこの経路を使っている。**

→ **対処**: `ARG USER_UID=1000` / `ARG USER_GID=1000` と既定値を付け、理由をコメントに残した。

### F2: `${UID:-1000}` は既定のシェルでは**常に 1000**になる（既存の問題。本 issue で顕在化）

`docker-compose.yml:15-16` の `USER_UID: ${UID:-1000}` は、`UID` が
**エクスポートされていないと機能しない**。zsh / bash とも既定ではエクスポートしないため、
素の `docker compose build` では常に 1000:1000 になる。

**V5 / V16 / V17 / V18 で記録した 502:20 は、既定手順の再現値ではない**（実行時に
`UID` / `GID` を明示的に渡していたことによる）。
**同じ文書内に 502 と 1000 の両方が出てくるのはこのため**で、
build-arg を渡したかどうかの違いである（F1 の再検証と F3 の測定は渡していないので 1000）。
明記しておかないと追試した人が値の差で混乱する。

実害: **Linux ホストで uid≠1000 のユーザーが `docker compose run` を使うと `/workspace` に
書けなくなる**（変更前は root だったので書けていた）。

→ **対処**: 本 issue では**直さない**。compose 単体では UID を検出できず、
修正は「ホスト側で `export UID GID` させる」等の運用要求か compose 構成の変更になり、
**#141 のスコープ（非 root 化）を超える**。事実として記録し、必要なら別 issue にする。

**★ 「主経路では問題が出ない」と書きかけたが、それは言えない（F4 と同じ誤りの再発）。**
一度は「`devcontainer up` 経由では問題が出ないことを V18 で確認済み」と書いた。しかし
**V18 は macOS での測定で、UID 写像により誰がどう作っても書けてしまう**。V17 と同じく
**検出力ゼロ**であり、F2 の実害（Linux ホストで uid≠1000）を検出できる測定ではない。

正しくは: **Linux ホストでは `updateRemoteUserUID: true` が UID を合わせるはずだが、未測定。**
実際、macOS での実測では `devcontainer up` 後も `uid=1000`（ホストは 502）のままで、
**`updateRemoteUserUID` は発火していない**（CLI 仕様どおり Linux ホスト限定の機構）。
この確認も **#142（user-action）** の対象に含まれる。

### F3: 「docker socket に到達できる」は**推論であって実測ではなかった**

V18 で `groups=...,991(docker)` を観測し、そこから「sudo 無しで socket に到達できる」と
書いていたが、これはグループ所属からの**推論**。実際に `docker ps` を通していない。
この主張は #64 の訂正コメントの根拠として使っているため、**実測で裏を取る**。

**F3 の実測**（修正後の `devcontainer up` で起動したコンテナ内、`sudo` を一切使わず）:

```
$ id
uid=1000(vscode) gid=1000(vscode) groups=1000(vscode),991(docker)

$ docker ps --format '{{.Names}}'      # sudo なし
issue141_devcontainer-devcontainer-1
com_bio_vag_visualization_devcontainer-devcontainer-1
devcontainer-devcontainer-1            # ← 他プロジェクトのコンテナまで見える

$ docker run --rm -v /:/host alpine:latest ls /host    # sudo なし
Users  Volumes  bin  boot  ...
```

**推論ではなく実測として確認できた。** 非 root の `vscode` は sudo 無しで
Docker API を叩け、任意のパスを mount した新しいコンテナを起動できる。
`NOPASSWD` を外してもこの経路は塞がらない、という #64 の訂正の根拠が裏付けられた。

**★ 表現の精度**: この `-v /:/host` で見えているのは **Docker Desktop の Linux VM の
ルート**であって macOS のファイルシステムそのものではない。
ただし Linux ホストではこれが**ホストの `/` そのもの**になる。
いずれにせよ **devcontainer の隔離からは抜けている。**

### F4: `docs/security.md` に**未検証の断定**と**事実誤り**を書いていた

Step 4-2 の敵対的レビューで指摘された2件。どちらも本 issue の規律面の価値を損なうもの。

1. **「root 権限は `sudo` を明示したときだけ得られます」は誤り。**
   `docker exec -u 0` / `docker run --user root` で sudo 無しに root になれる。
   **`USER` 指定は既定値であって境界ではない。** セキュリティ文書で保証範囲を
   過大に書くのは、`|| true` で失敗を隠すのと同種の害がある
2. **「`/workspace` に root 所有ファイルが残らない」を緩和要因として断定していた。**
   これは V17 で「この環境では判定不能」と記録した内容そのもので、
   **仕様側で踏みとどまった判断がドキュメント側で既成事実に格上げされていた。**
   しかも §7 は `sudo NOPASSWD` の節であり、**sudo で破れる主張を
   sudo のリスクの緩和要因に挙げる**という構造的矛盾でもあった

→ **対処**: 「既定では非 root」「保証ではなく既定の改善」に書き換え、
`-u 0` で root になれることを明記した。

### F5: GPU 実機の未測定分は user-action issue に切り出した

auto-reviewer の承認条件だった follow-up 起票が未了だったため、**#142** を起票し
`validation` ＋ `user-action` ラベルを付けて #139 の子にリンクした。
`user-action` は `/task-run` の自動処理でスキップされる。
