#!/usr/bin/env bash
# devcontainer の PID 1 が init（tini）であることを固定する回帰テスト
# 由来: 派生プロジェクト delta-clip-dev #165
#
# PID 1 が keep-alive の `sleep` のままだと孤児プロセスを reap できず、
# devcontainer.json の shutdownAction: none と相まってゾンビが際限なく溜まる。
# .devcontainer/ は /template-sync が「差分表示→選択適用」で扱うため、
# init: true が巻き戻る経路が実在する。静的に pin して守る。
#
# docker daemon は不要（docker compose config はローカル解析のみ）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="$ROOT/.devcontainer"

if ! docker compose version >/dev/null 2>&1; then
  echo "SKIP: docker compose が使えないため検証できません"
  exit 0
fi

if [ ! -f "$DC/docker-compose.yml" ]; then
  echo "FAIL: $DC/docker-compose.yml が無い"
  exit 1
fi

# 合成結果から devcontainer サービスのブロックだけを取り出す。
# `docker compose config` の出力ではサービスは services: の下に 2 スペースで並ぶので、
# 次の 2 スペース始まりのキーまでを 1 サービスとみなす。
# ★ 全文 grep にしないこと。他サービスの init: true や、環境変数に紛れた
#   "sleep" という文字列で通ってしまう。
extract_service() {
  awk '
    /^  devcontainer:$/ { in_svc = 1; next }
    in_svc && /^  [A-Za-z_]/ { in_svc = 0 }
    in_svc { print }
  '
}

fail=0
checked=0

for override in "$DC"/*/docker-compose.override.yml; do
  [ -f "$override" ] || continue
  variant=$(basename "$(dirname "$override")")
  checked=$((checked + 1))

  # 合成失敗を「init: true が無い」と誤報しないよう、stderr を捨てずに区別する
  if ! out=$(docker compose -f "$DC/docker-compose.yml" -f "$override" config 2>&1); then
    echo "FAIL: $variant の compose 合成に失敗した"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=1
    continue
  fi

  svc=$(printf '%s\n' "$out" | extract_service)
  if [ -z "$svc" ]; then
    echo "FAIL: $variant の合成結果に devcontainer サービスが無い"
    fail=1
    continue
  fi

  if printf '%s\n' "$svc" | grep -qE '^[[:space:]]+init: true$'; then
    echo "PASS: $variant → devcontainer.init: true"
  else
    echo "FAIL: $variant の devcontainer サービスに 'init: true' が無い"
    echo "      PID 1 が sleep になり孤児を reap できずゾンビが溜まる（delta-clip-dev #165）"
    fail=1
  fi

  # keep-alive が残っていること。NVIDIA entrypoint は CMD=null にするため、
  # command が消えるとコンテナが即終了する。
  if printf '%s\n' "$svc" | grep -qE '^[[:space:]]+- sleep$'; then
    echo "PASS: $variant → devcontainer.command に keep-alive がある"
  else
    echo "FAIL: $variant の devcontainer.command から keep-alive（sleep）が消えている"
    fail=1
  fi
done

# ★ 0 件で PASS にしないこと。「検査対象が無いのに実行済みとして数える」のは
#   quality-check.sh が禁じている「失敗0件と実行0件の混同」そのもの。
if [ "$checked" -eq 0 ]; then
  echo "FAIL: .devcontainer/*/docker-compose.override.yml が1つも見つからない"
  fail=1
fi

exit $fail
