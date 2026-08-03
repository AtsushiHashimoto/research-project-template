# ============================================================
# [Template] research-project-template 共通 Dockerfile
# CPU/GPU 両対応: BASE_IMAGE で切り替え
# ============================================================
# ★ BASE_IMAGE に既定値を置かない（#140 D2a）。
#   版は CPU / GPU で異なるため、正しい所有者は各 `*/docker-compose.override.yml` 側であり、
#   ここに既定値を書くと**同じ版が2箇所に出て**、上げるときに片方だけ直る事故が起きる
#   （単一情報源の原則）。
#   未指定でビルドすると `FROM ${BASE_IMAGE}` が空になり **即座に落ちる**（fail-fast）。
#   #141 の空 ARG 問題（`getent` を素通りして壊れたイメージが完成してしまう）とは異なり、
#   ここは黙って壊れないため既定値なしで安全。
#   compose を経ない直接ビルドでは `--build-arg BASE_IMAGE=...` を必ず渡すこと。
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# 開発に必要なツールをインストール
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    git-lfs \
    jq \
    ripgrep \
    fzf \
    tree \
    htop \
    sudo \
    tmux \
    shellcheck \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 非rootユーザーを作成（既存のUID/GIDがあれば再利用）
# ★ USER_UID / USER_GID に既定値が必須（#141）。
#   これらが空だと `getent group`（引数なし）が exit 0 を返すため、
#   **vscode ユーザーが作られないままビルドが成功する**。
#   末尾で `USER $USERNAME` に切り替えるようになったので、その状態のイメージは
#   起動時に必ず `unable to find user vscode` で落ちる（以前は USER 行が無く root で動いていた）。
#   compose 経由では `USER_UID: ${UID:-1000}` が渡るが、
#   `docker build` を直接叩く経路（GPU の platform 指定ビルド等）では渡らない。
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
RUN if getent group $USER_GID > /dev/null; then \
        EXISTING_GROUP=$(getent group $USER_GID | cut -d: -f1); \
    else \
        groupadd --gid $USER_GID $USERNAME; \
        EXISTING_GROUP=$USERNAME; \
    fi && \
    if getent passwd $USER_UID > /dev/null; then \
        EXISTING_USER=$(getent passwd $USER_UID | cut -d: -f1); \
        usermod -l $USERNAME -d /home/$USERNAME -m $EXISTING_USER 2>/dev/null || true; \
    else \
        useradd --uid $USER_UID --gid $USER_GID -m $USERNAME; \
    fi && \
    echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME

# GitHub CLI をインストール
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# uv をインストール（高速Pythonパッケージマネージャー）
# UV_INSTALL_DIR=/usr/local/bin: 既定の /root/.local/bin だと、末尾の USER 切り替え後に
#   非 root から /root が読めず uv が消える（#141）。/usr/local/bin は既定 PATH に含まれるため
#   ENV PATH の追記も不要になる。symlink での二重管理はインストール先と参照先が2箇所になり
#   uv 更新時に片方だけ変わりうるため採らない（単一情報源の原則）
# INSTALLER_NO_MODIFY_PATH=1: システムパスに入れる以上インストーラによる ~/.bashrc への
#   PATH 追記は不要。root のホームに副作用を残さない
#
# ★ 版は固定しない（#140「変更しないもの（スコープ外）」表）。
#   uv は**開発ツールであり実験の数値に影響しない**。
#   固定すると全派生プロジェクトが同時に古くなり、CI が無いため自動更新の仕組みも作れない。
#   固定するのは数値再現性に効くもの（torch）とビルドの土台（ベースイメージ）だけに絞る。
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh

# Node.js 20をインストール（Claude Code用）
# ★ マイナー/パッチは固定しない（#140 D4）。`setup_20.x` は**メジャー固定**であり
#   「無指定」ではない。claude-code の実行環境であって実験の数値に影響せず、
#   マイナー/パッチ差で壊れる性質のものでもない。メジャーを跨ぐ更新だけ手で判断すれば足りる。
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 新しいNode.jsを確実に優先させる
ENV PATH="/usr/bin:${PATH}"

# Claude Codeをグローバルインストール
# ★ 版は固定しない（#140 D3）。**積極的にそう決めている**（付け忘れではない）:
#   - 更新が頻繁で、固定するとレート制限対応やモデル追加といった
#     **実運用に直結する更新を逃す**
#   - 開発ツールであり、実験の数値再現性に寄与しない
#   - テンプレートが版を決め打つと全派生プロジェクトが**同時に古くなる**
RUN npm install -g @anthropic-ai/claude-code

# tmux設定（マウススクロール有効化）
RUN echo 'set -g mouse on' >> /etc/tmux.conf

# Note: --dangerously-skip-permissions は post-start.sh の claude() ラッパーで付与
# alias は claude-auto-retry の shell wrapper (claude() 関数) と競合するため設定しない

# CPU-only PyTorch をインストール（GPUベースイメージ以外の場合）
ARG INSTALL_TORCH_CPU=false
# ★ torch は固定する（#140 D1）。版が変わると**数値が変わりうる**ため、
#   本テンプレートで唯一「数値再現性のために固定する」対象。
#   既定値はテンプレートの初期値にすぎない（#141 の実測で実際に入った版）。
# ★ `+cpu` ローカル版指定子は付けないこと。`--index-url .../whl/cpu` の下では
#   `torch==X.Y.Z` が `X.Y.Z+cpu` に解決される。`==X.Y.Z+cpu` と書くと
#   GPU 用インデックスへ切り替えたときに解決不能になり、
#   **インデックス URL と版指定の2箇所を同時に直す**必要が出る（単一情報源に反する）。
# ★ Fallback は置かない。存在しない版を指定したらビルドは落ちるべきで、
#   「取れなければ最新で続行」は固定の目的そのものを無効化する。
# ★ 版が書いてあるのは**次の1行だけ**。ドキュメントには版を再掲しないこと
#   （再掲すると、版を上げたときにドキュメントだけ古くなる）。
#
# --- [Project] 次の1行がプロジェクト所有。実験の再現性に直結するため版を決めて固定すること ---
ARG TORCH_VERSION=2.13.0
# --- [Project] ここまで ---
RUN if [ "$INSTALL_TORCH_CPU" = "true" ]; then \
    pip install "torch==${TORCH_VERSION}" --index-url https://download.pytorch.org/whl/cpu; \
fi

# ============================================================
# ここから非 root（#141）
# ============================================================
# USER が無いとコンテナの主プロセスが root で動く。devcontainer.json の
# `remoteUser: vscode` は VS Code 経由のシェルにしか効かないため、
# `docker compose run` / `docker exec` を直接叩くと root になり、
# bind mount した /workspace（＝ホストのリポジトリ）に root 所有ファイルが残る。
# macOS の Docker Desktop は UID を写像するため症状が出にくいが、
# Linux ホストや共同研究者の環境では以後の git 操作・ファイル削除が権限エラーで止まる。
#
# 上流の apt-get / npm install -g / pip install は root が必要なため、
# ビルド段階は root のままにし、**末尾でだけ**切り替える。
# ユーザー名は上で定義した ARG USERNAME を再利用する（2箇所に書かない）。
# sudo NOPASSWD は維持しており（#64 で見送りと判断済み）、
# post-create.sh が依存する sudo 6箇所と docker-outside-of-docker feature の
# socket 権限調整はそのまま動く。
#
# ★ 追加の RUN / COPY はこのブロックより**上**に置くこと。
#   ここより下に書くと非 root で実行され、apt-get / npm -g / pip が権限エラーで落ちる。
#   --- [Project] プロジェクト固有の追加インストールは、この行より上に追記 ---
WORKDIR /workspace
USER $USERNAME
