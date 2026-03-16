#!/bin/bash
# CI 脚本：创建 MR 到配置仓库（用于 test/staging/prod 推进）
# 用法：./create-promotion-mr.sh <service> <domain> <env> <new-tag> <initiator>
# 需要环境变量：GITOPS_REPO_URL, DEPLOY_TOKEN_USER, DEPLOY_TOKEN, GITLAB_API_URL, GITLAB_TOKEN, GITOPS_PROJECT_ID

set -euo pipefail

SERVICE="$1"
DOMAIN="$2"
ENV="$3"
NEW_TAG="$4"
INITIATOR="${5:-ci-bot}"

OVERLAY_FILE="services/${DOMAIN}/${SERVICE}/overlays/${ENV}/kustomization.yaml"
BRANCH_NAME="promote/${SERVICE}-${ENV}-${NEW_TAG}"
WORK_DIR=$(mktemp -d)
trap "rm -rf ${WORK_DIR}" EXIT

echo "==> Cloning gitops repo..."
git clone "https://${DEPLOY_TOKEN_USER}:${DEPLOY_TOKEN}@${GITOPS_REPO_URL#https://}" "${WORK_DIR}/gitops-repo"
cd "${WORK_DIR}/gitops-repo"

echo "==> Creating branch ${BRANCH_NAME}..."
git checkout -b "${BRANCH_NAME}"

echo "==> Updating ${OVERLAY_FILE} newTag to ${NEW_TAG}..."
sed -i.bak "s/newTag: \".*\"/newTag: \"${NEW_TAG}\"/" "${OVERLAY_FILE}"
rm -f "${OVERLAY_FILE}.bak"

git add "${OVERLAY_FILE}"
git commit -m "[devops-skill] promote ${SERVICE} to ${ENV} with tag ${NEW_TAG}"
git push origin "${BRANCH_NAME}"

echo "==> Creating MR..."
MR_BODY=$(cat <<EOF
## 环境推进

**发起人**: ${INITIATOR}
**意图**: 将 ${SERVICE} 部署到 ${ENV} 环境
**镜像 tag**: ${NEW_TAG}
**影响范围**: services/${DOMAIN}/${SERVICE}/overlays/${ENV}/

### 变更内容
- 更新 ${ENV} overlay 的 images.newTag 为 ${NEW_TAG}
EOF
)

curl --silent --fail \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --data-urlencode "source_branch=${BRANCH_NAME}" \
  --data-urlencode "target_branch=main" \
  --data-urlencode "title=promote: ${SERVICE} → ${ENV} (${NEW_TAG})" \
  --data-urlencode "description=${MR_BODY}" \
  "${GITLAB_API_URL}/projects/${GITOPS_PROJECT_ID}/merge_requests"

echo "==> MR created successfully"
