#!/usr/bin/env bash
#
# ADK 公式スキル (google/agents-cli) を .claude/skills/ に動的取得する。
#
# - 取得対象: 7 つの google-agents-cli-* スキル
# - 配布元 : https://github.com/google/agents-cli (Apache License 2.0)
# - 取得方法: `npx skills add google/agents-cli --copy` でプロジェクトに実体コピー
# - git 管理: 取得物は .gitignore で除外（コミットしない／常に最新を取得）
#
# 使い方:
#   ./scripts/install-adk-skills.sh           # 既に存在すればスキップ
#   ./scripts/install-adk-skills.sh --force   # 強制再取得（最新化）
#
# 実行後に Claude Code を /clear で再起動するとスキルが認識される。

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="${PROJECT_ROOT}/.claude/skills"
MARKER="${SKILL_DIR}/google-agents-cli-adk-code/SKILL.md"

# Claude Code 以外のエージェント用ディレクトリは npx skills add の副作用で生成される。
# プロジェクトを汚染するので毎回掃除する。
SIDE_EFFECT_DIRS=(
    .adal .agents .aider-desk .augment .bob .codeartsdoer .codebuddy .codemaker
    .codestudio .commandcode .continue .cortex .crush .devin .factory .forge
    .goose .iflow .junie .kilocode .kiro .kode .mcpjam .mux .neovate .openhands
    .pi .pochi .qoder .qwen .roo .rovodev .tabnine .trae .vibe .windsurf
    .zencoder skills
)

cleanup_side_effects() {
    cd "${PROJECT_ROOT}"
    local removed=0
    for d in "${SIDE_EFFECT_DIRS[@]}"; do
        if [[ -d "${d}" ]]; then
            rm -rf "${d}"
            removed=$((removed + 1))
        fi
    done
    if [[ ${removed} -gt 0 ]]; then
        echo "  ✓ 副作用ディレクトリを ${removed} 個削除しました"
    fi
}

# 既存チェック
FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

if [[ -f "${MARKER}" ]] && [[ "${FORCE}" == "false" ]]; then
    echo "✓ ADK スキルは既にインストール済みです: ${SKILL_DIR}/google-agents-cli-*"
    echo "  最新化したい場合は: $0 --force"
    cleanup_side_effects
    exit 0
fi

# 依存ツール確認
if ! command -v npx >/dev/null 2>&1; then
    echo "❌ npx が見つかりません。Node.js をインストールしてください。" >&2
    exit 1
fi

echo "━━━ Google ADK スキル取得 ━━━"
echo "  取得元: https://github.com/google/agents-cli (Apache 2.0)"
echo "  配置先: ${SKILL_DIR}/google-agents-cli-*"
echo ""

cd "${PROJECT_ROOT}"
npx -y skills add google/agents-cli --skill '*' --agent claude --copy --yes

echo ""
echo "━━━ 副作用ディレクトリの掃除 ━━━"
cleanup_side_effects

echo ""
echo "━━━ 完了 ━━━"
ls -1 "${SKILL_DIR}" | grep '^google-agents-cli-' | sed 's/^/  ✓ /'

cat <<'EOF'

━━━ 次のステップ ━━━
取得した Skill を Claude Code に認識させるため、セッションを /clear してください。
その後、/generate-a2ui-frontend を実行すると ADK 関連の判断で Google 公式スキルが使われます。
EOF
