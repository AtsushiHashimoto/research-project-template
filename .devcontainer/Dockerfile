# ベースイメージ（必要に応じて変更）
# GPU使用の場合: nvcr.io/nvidia/pytorch:24.12-py3
# CPU only の場合: python:3.11-slim
FROM nvcr.io/nvidia/pytorch:24.12-py3

# 開発に必要なツールをインストール
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    jq \
    ripgrep \
    fzf \
    tree \
    htop \
    sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 非rootユーザーを作成（既存のUID/GIDがあれば再利用）
ARG USERNAME=vscode
ARG USER_UID
ARG USER_GID
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

# Node.js 20をインストール（Claude Code用）
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 新しいNode.jsを確実に優先させる
ENV PATH="/usr/bin:${PATH}"

# Claude Codeをグローバルインストール
RUN npm install -g @anthropic-ai/claude-code

# claudeコマンドのaliasを設定（全ユーザー向け）
RUN echo 'alias claude="claude --dangerously-skip-permissions"' >> /etc/bash.bashrc
