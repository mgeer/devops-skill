#!/bin/bash
# CI 脚本：更新 dev overlay 镜像 tag（直推 main）
# 用法：./update-dev-tag.sh <service> <domain> <new-tag>
# 需要环境变量：GITOPS_REPO_URL, DEPLOY_TOKEN_USER, DEPLOY_TOKEN

set -euo pipefail

SERVICE="$1"
DOMAIN="$2"
NEW_TAG="$3"
MAX_RETRIES=3

OVERLAY_FILE="services/${DOMAIN}/${SERVICE}/overlays/dev/kustomization.yaml"
WORK_DIR=$(mktemp -d)
trap "rm -rf ${WORK_DIR}" EXIT

echo "==> Cloning gitops repo..."
git clone "https://${DEPLOY_TOKEN_USER}:${DEPLOY_TOKEN}@${GITOPS_REPO_URL#https://}" "${WORK_DIR}/gitops-repo"
cd "${WORK_DIR}/gitops-repo"

echo "==> Updating ${OVERLAY_FILE} newTag to ${NEW_TAG}..."
# 使用 sed 更新 newTag 字段
sed -i.bak "s/newTag: \".*\"/newTag: \"${NEW_TAG}\"/" "${OVERLAY_FILE}"
rm -f "${OVERLAY_FILE}.bak"

git add "${OVERLAY_FILE}"
git commit -m "ci: update ${SERVICE} image to ${NEW_TAG}"

# 重试逻辑：处理并发冲突
for i in $(seq 1 ${MAX_RETRIES}); do
  echo "==> Push attempt ${i}/${MAX_RETRIES}..."
  if git push origin main; then
    echo "==> Successfully pushed to main"
    exit 0
  fi
  echo "==> Push failed, pulling with rebase..."
  git pull --rebase origin main
done

echo "==> ERROR: Failed to push after ${MAX_RETRIES} attempts"
exit 1
