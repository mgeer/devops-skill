#!/bin/bash
# 代码仓库 CI 中检测 .devops.yaml 变更的脚本
# 在 CI pipeline 中调用，检测到变更时输出提醒（不阻塞 CI）

set -euo pipefail

if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q '^\.devops\.yaml$'; then
  echo ""
  echo "============================================"
  echo "  检测到 .devops.yaml 变更"
  echo "  请运行 /devops 同步到配置仓库"
  echo "============================================"
  echo ""
fi
