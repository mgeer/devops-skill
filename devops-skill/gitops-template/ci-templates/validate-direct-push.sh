#!/bin/bash
# 配置仓库 CI 校验脚本：检测直推 commit 的 diff 范围
# 用于配置仓库自身的 CI pipeline，确保直推只修改了允许的范围
# 违规时输出告警（不阻塞，但通知平台团队）

set -euo pipefail

# 获取最新 commit 的 diff
CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")

if [ -z "${CHANGED_FILES}" ]; then
  echo "==> No changes detected"
  exit 0
fi

VIOLATIONS=""

while IFS= read -r file; do
  # 允许的范围：overlays/int/kustomization.yaml
  if echo "${file}" | grep -qE '^services/.+/overlays/int/kustomization\.yaml$'; then
    # 检查是否只修改了 images 相关字段
    DIFF_CONTENT=$(git diff HEAD~1 HEAD -- "${file}")
    if echo "${DIFF_CONTENT}" | grep -qE '^\+.*' | grep -vqE '(newTag|newName|^\+\+\+|^\+$)'; then
      VIOLATIONS="${VIOLATIONS}\n  WARNING: ${file} — modified more than just images fields"
    fi
  elif echo "${file}" | grep -qE '^services/.+/overlays/(test|staging|prod)/'; then
    VIOLATIONS="${VIOLATIONS}\n  VIOLATION: ${file} — non-int overlay modified via direct push"
  elif echo "${file}" | grep -qE '^(infrastructure|argocd)/'; then
    VIOLATIONS="${VIOLATIONS}\n  VIOLATION: ${file} — protected directory modified via direct push"
  fi
done <<< "${CHANGED_FILES}"

if [ -n "${VIOLATIONS}" ]; then
  echo "==> CI Direct Push Scope Violations detected:"
  echo -e "${VIOLATIONS}"
  echo ""
  echo "==> Direct push should only modify overlays/int/ image tags."
  echo "==> All other changes must go through MR."
  # 不阻塞，但可以在这里添加通知逻辑（如 Slack webhook）
  exit 0
fi

echo "==> Direct push scope validation passed"
