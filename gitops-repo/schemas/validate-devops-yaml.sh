#!/bin/bash
# 校验 .devops.yaml 的语义规则（JSON Schema 之外的业务规则）
# 用法：./validate-devops-yaml.sh <devops-yaml-path> <platform-inventory-path>

set -euo pipefail

DEVOPS_YAML="${1:-.devops.yaml}"
INVENTORY="${2:-platform-inventory.yaml}"

if [ ! -f "${DEVOPS_YAML}" ]; then
  echo "ERROR: ${DEVOPS_YAML} not found"
  exit 1
fi

if [ ! -f "${INVENTORY}" ]; then
  echo "WARNING: ${INVENTORY} not found, skipping domain/team validation"
  exit 0
fi

ERRORS=0

# 检查 1: domain 是否在 platform-inventory.yaml 中存在
DOMAIN=$(grep 'domain:' "${DEVOPS_YAML}" | head -1 | awk '{print $2}')
if [ -n "${DOMAIN}" ]; then
  if ! grep -q "name: ${DOMAIN}" "${INVENTORY}"; then
    echo "ERROR: domain '${DOMAIN}' not found in platform-inventory.yaml"
    ERRORS=$((ERRORS + 1))
  fi
fi

# 检查 2: dependencies 中 role 和 type 组合是否合法
# 合法组合：mysql+owner, mysql+consumer, redis+owner, redis+consumer,
#           kafka-topic+producer, kafka-topic+consumer
# 不合法：mysql+producer, redis+producer, kafka-topic+owner
while IFS= read -r line; do
  TYPE=$(echo "${line}" | grep -oP 'type:\s*\K\S+' || true)
  ROLE=$(echo "${line}" | grep -oP 'role:\s*\K\S+' || true)

  if [ "${TYPE}" = "mysql" ] && [ "${ROLE}" = "producer" ]; then
    echo "ERROR: invalid combination type=mysql role=producer (use 'owner' for MySQL)"
    ERRORS=$((ERRORS + 1))
  elif [ "${TYPE}" = "redis" ] && [ "${ROLE}" = "producer" ]; then
    echo "ERROR: invalid combination type=redis role=producer (use 'owner' for Redis)"
    ERRORS=$((ERRORS + 1))
  elif [ "${TYPE}" = "kafka-topic" ] && [ "${ROLE}" = "owner" ]; then
    echo "ERROR: invalid combination type=kafka-topic role=owner (use 'producer' for Kafka)"
    ERRORS=$((ERRORS + 1))
  fi
done < <(grep -A2 '^\s*- name:' "${DEVOPS_YAML}" | paste - - - || true)

# 检查 3: migration_path 有值时，dependencies 中需有 mysql role=owner
MIGRATION_PATH=$(grep 'migration_path:' "${DEVOPS_YAML}" | head -1 | awk '{print $2}' || true)
if [ -n "${MIGRATION_PATH}" ]; then
  if ! grep -A2 'type: mysql' "${DEVOPS_YAML}" | grep -q 'role: owner'; then
    echo "WARNING: migration_path is set but no MySQL owner dependency found. Flyway init container requires MySQL connection info."
    # 警告不阻塞，仅提示
  fi
fi

if [ ${ERRORS} -gt 0 ]; then
  echo "Validation failed with ${ERRORS} error(s)"
  exit 1
fi

echo "Validation passed"
