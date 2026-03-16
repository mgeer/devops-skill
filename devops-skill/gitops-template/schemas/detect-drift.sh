#!/bin/bash
# 漂移检测脚本：对比 .devops.yaml 与配置仓库现状，输出差异
# 用法：./detect-drift.sh <devops-yaml-path> <gitops-repo-path>
#
# 检测项：
#   1. 服务目录是否存在
#   2. 各环境 overlay 是否齐全
#   3. dependencies 中声明的资源是否在配置仓库中存在
#   4. base deployment 的关键字段是否与 .devops.yaml 一致（服务名、端口、健康检查）

set -euo pipefail

DEVOPS_YAML="${1:-.devops.yaml}"
GITOPS_REPO="${2:-}"

if [ ! -f "${DEVOPS_YAML}" ]; then
  echo "ERROR: ${DEVOPS_YAML} not found"
  exit 1
fi

if [ -z "${GITOPS_REPO}" ] || [ ! -d "${GITOPS_REPO}" ]; then
  echo "ERROR: gitops-repo path required (usage: $0 <devops-yaml> <gitops-repo-path>)"
  exit 1
fi

DRIFTS=0

# 解析 .devops.yaml 基本字段
SERVICE=$(grep '^\s*name:' "${DEVOPS_YAML}" | head -1 | awk '{print $2}')
DOMAIN=$(grep '^\s*domain:' "${DEVOPS_YAML}" | head -1 | awk '{print $2}')
PORT=$(grep '^\s*port:' "${DEVOPS_YAML}" | head -1 | awk '{print $2}')
HEALTH_CHECK=$(grep '^\s*health_check:' "${DEVOPS_YAML}" | head -1 | awk '{print $2}')
HEALTH_CHECK="${HEALTH_CHECK:-/healthz}"

echo "=== 漂移检测: ${SERVICE} (domain: ${DOMAIN}) ==="
echo ""

# --- 检测 1: 服务目录 ---
SERVICE_BASE="${GITOPS_REPO}/services/${DOMAIN}/${SERVICE}/base"
if [ ! -d "${SERVICE_BASE}" ]; then
  echo "DRIFT: 服务 base 目录不存在: services/${DOMAIN}/${SERVICE}/base/"
  DRIFTS=$((DRIFTS + 1))
else
  echo "OK: 服务 base 目录存在"

  # 检查 base 文件完整性
  for f in deployment.yaml service.yaml ingress.yaml kustomization.yaml; do
    if [ ! -f "${SERVICE_BASE}/${f}" ]; then
      echo "DRIFT: base 文件缺失: ${f}"
      DRIFTS=$((DRIFTS + 1))
    fi
  done

  # 检查 deployment 中的端口和健康检查路径
  if [ -f "${SERVICE_BASE}/deployment.yaml" ]; then
    DEPLOY_PORT=$(grep 'containerPort:' "${SERVICE_BASE}/deployment.yaml" | head -1 | awk -F'containerPort:' '{print $2}' | awk '{print $1}')
    if [ "${DEPLOY_PORT}" != "${PORT}" ]; then
      echo "DRIFT: 端口不一致 — .devops.yaml: ${PORT}, deployment: ${DEPLOY_PORT}"
      DRIFTS=$((DRIFTS + 1))
    fi

    DEPLOY_HEALTH=$(grep -A3 'livenessProbe:' "${SERVICE_BASE}/deployment.yaml" | grep 'path:' | head -1 | awk '{print $2}' || true)
    if [ -n "${DEPLOY_HEALTH}" ] && [ "${DEPLOY_HEALTH}" != "${HEALTH_CHECK}" ]; then
      echo "DRIFT: 健康检查路径不一致 — .devops.yaml: ${HEALTH_CHECK}, deployment: ${DEPLOY_HEALTH}"
      DRIFTS=$((DRIFTS + 1))
    fi
  fi
fi

# --- 检测 2: 各环境 overlay ---
ENVS="int test staging prod"
SERVICE_OVERLAYS="${GITOPS_REPO}/services/${DOMAIN}/${SERVICE}/overlays"
for env in ${ENVS}; do
  OVERLAY="${SERVICE_OVERLAYS}/${env}/kustomization.yaml"
  if [ ! -f "${OVERLAY}" ]; then
    echo "DRIFT: overlay 缺失: services/${DOMAIN}/${SERVICE}/overlays/${env}/kustomization.yaml"
    DRIFTS=$((DRIFTS + 1))
  fi
done

# --- 检测 3: dependencies 对应的资源目录 ---

# 资源目录检查函数
check_resource_exists() {
  local target_domain="$1"
  local dep_type="$2"
  local dep_name="$3"
  local dep_role="$4"

  # kafka-topic 在路径中用 kafka
  local type_dir="${dep_type}"
  if [ "${type_dir}" = "kafka-topic" ]; then
    type_dir="kafka"
  fi

  local resource_base="${GITOPS_REPO}/resources/${target_domain}/${type_dir}/${dep_name}/base"

  if [ "${dep_role}" = "owner" ] || [ "${dep_role}" = "producer" ]; then
    # owner/producer: 资源目录 MUST 存在
    if [ ! -d "${resource_base}" ]; then
      echo "DRIFT: ${dep_role} 资源目录不存在: resources/${target_domain}/${type_dir}/${dep_name}/base/"
      DRIFTS=$((DRIFTS + 1))
    else
      echo "OK: ${dep_role} 资源存在: ${dep_name} (${dep_type})"
      # 检查各环境 overlay
      for env in ${ENVS}; do
        local res_overlay="${GITOPS_REPO}/resources/${target_domain}/${type_dir}/${dep_name}/overlays/${env}/kustomization.yaml"
        if [ ! -f "${res_overlay}" ]; then
          echo "DRIFT: 资源 overlay 缺失: resources/${target_domain}/${type_dir}/${dep_name}/overlays/${env}/"
          DRIFTS=$((DRIFTS + 1))
        fi
      done
    fi
  else
    # consumer: 资源目录 SHOULD 存在（别人创建的）
    if [ ! -d "${resource_base}" ]; then
      echo "WARN: consumer 引用的资源不存在: resources/${target_domain}/${type_dir}/${dep_name}/ — 可能尚未创建"
    else
      echo "OK: consumer 引用资源存在: ${dep_name} (${dep_type})"
    fi
  fi
}

# 解析 dependencies 块（逐行状态机）
IN_DEPS=0
DEP_NAME=""
DEP_TYPE=""
DEP_ROLE=""
DEP_DOMAIN=""

while IFS= read -r line; do
  # 进入 dependencies 块
  if echo "${line}" | grep -q '^dependencies:'; then
    IN_DEPS=1
    continue
  fi

  # 离开 dependencies 块（遇到非缩进的顶层 key）
  if [ ${IN_DEPS} -eq 1 ] && echo "${line}" | grep -qE '^[a-z]'; then
    if [ -n "${DEP_NAME}" ] && [ -n "${DEP_TYPE}" ]; then
      TARGET_DOMAIN="${DEP_DOMAIN:-${DOMAIN}}"
      check_resource_exists "${TARGET_DOMAIN}" "${DEP_TYPE}" "${DEP_NAME}" "${DEP_ROLE}"
    fi
    IN_DEPS=0
    continue
  fi

  if [ ${IN_DEPS} -eq 0 ]; then
    continue
  fi

  # 解析 dependency 条目
  if echo "${line}" | grep -q '^\s*- name:'; then
    # 先处理前一个 dependency
    if [ -n "${DEP_NAME}" ] && [ -n "${DEP_TYPE}" ]; then
      TARGET_DOMAIN="${DEP_DOMAIN:-${DOMAIN}}"
      check_resource_exists "${TARGET_DOMAIN}" "${DEP_TYPE}" "${DEP_NAME}" "${DEP_ROLE}"
    fi
    DEP_NAME=$(echo "${line}" | awk '{print $3}')
    DEP_TYPE=""
    DEP_ROLE=""
    DEP_DOMAIN=""
  elif echo "${line}" | grep -q '^\s*type:'; then
    DEP_TYPE=$(echo "${line}" | awk '{print $2}')
  elif echo "${line}" | grep -q '^\s*role:'; then
    DEP_ROLE=$(echo "${line}" | awk '{print $2}')
  elif echo "${line}" | grep -q '^\s*domain:'; then
    DEP_DOMAIN=$(echo "${line}" | awk '{print $2}')
  fi
done < "${DEVOPS_YAML}"

# 处理文件末尾的最后一个 dependency
if [ ${IN_DEPS} -eq 1 ] && [ -n "${DEP_NAME}" ] && [ -n "${DEP_TYPE}" ]; then
  TARGET_DOMAIN="${DEP_DOMAIN:-${DOMAIN}}"
  check_resource_exists "${TARGET_DOMAIN}" "${DEP_TYPE}" "${DEP_NAME}" "${DEP_ROLE}"
fi

# --- 汇总 ---
echo ""
if [ ${DRIFTS} -gt 0 ]; then
  echo "检测到 ${DRIFTS} 处漂移，请运行 /devops 同步"
  exit 1
else
  echo "无漂移，.devops.yaml 与配置仓库一致"
  exit 0
fi
