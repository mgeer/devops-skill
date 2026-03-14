## ADDED Requirements

### Requirement: Operator 自动生成 Secret 的命名约定

Operator 创建中间件实例时 SHALL 自动生成 K8s Secret，Secret 名称遵循固定命名约定。

| 中间件类型 | Secret 名称 | 包含的 key |
|-----------|------------|-----------|
| MySQL | `{instance-name}-secret` | `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` |
| Redis | `{instance-name}-secret` | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |

Kafka 集群内无认证，通过 `KAFKA_BOOTSTRAP` 环境变量连接，不需要 Secret。

#### Scenario: MySQL Operator 生成 Secret

- **WHEN** MySQL Operator 创建名为 order-db 的 InnoDBCluster 实例
- **THEN** Operator SHALL 自动生成名为 `order-db-secret` 的 K8s Secret，包含 `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`

#### Scenario: Redis Operator 生成 Secret

- **WHEN** Redis Operator 创建名为 order-cache 的 Redis 实例
- **THEN** Operator SHALL 自动生成名为 `order-cache-secret` 的 K8s Secret，包含 `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`

#### Scenario: Kafka 不需要 Secret

- **WHEN** AI 为服务添加 Kafka 依赖
- **THEN** AI SHALL 通过环境变量 `KAFKA_BOOTSTRAP`（值从 platform-inventory.yaml 获取）注入连接信息，不创建 Secret

---

### Requirement: envFrom 注入方式

AI SHALL 通过 Kustomize overlay 的 envFrom.secretRef 方式将 Secret 注入 Pod，不逐个声明环境变量。

#### Scenario: AI 添加 MySQL Secret 引用

- **WHEN** AI 为 order-service 添加 order-db 的 MySQL 依赖
- **THEN** AI SHALL 在 deployment overlay 中添加：
  ```yaml
  patches:
    - target:
        kind: Deployment
        name: order-service
      patch: |
        - op: add
          path: /spec/template/spec/containers/0/envFrom
          value:
            - secretRef:
                name: order-db-secret
  ```

#### Scenario: 多个 Secret 引用

- **WHEN** order-service 同时依赖 order-db（MySQL）和 order-cache（Redis）
- **THEN** deployment overlay 的 envFrom SHALL 包含两个 secretRef：`order-db-secret` 和 `order-cache-secret`

---

### Requirement: AI 不接触密码值

AI SHALL 永远不接触、不生成、不存储任何密码或凭证值。AI 只操作 Secret 的名称引用。

#### Scenario: AI 写 secretRef

- **WHEN** AI 为服务添加中间件依赖
- **THEN** AI SHALL 只在 overlay 中写入 `secretRef.name`（如 `order-db-secret`），不接触 Secret 的实际内容

#### Scenario: 用户询问密码

- **WHEN** 用户问"order-db 的密码是什么？"
- **THEN** AI SHALL 提示"密码由 Operator 自动生成并存储在 K8s Secret `order-db-secret` 中，可通过 `kubectl get secret order-db-secret -o yaml` 查看（需相应权限）"

---

### Requirement: 业务 Secret 处理

非 Operator 生成的 Secret（如第三方 API Key、业务凭证）SHALL 由开发者手动创建，AI 只负责添加引用。

#### Scenario: 用户需要第三方 API Key

- **WHEN** 开发者说"我的服务需要一个 Stripe API Key"
- **THEN** AI SHALL 引导：
  1. "请在 K8s 中手动创建 Secret（建议名称：{service}-stripe-secret），或通过 CI 变量注入"
  2. "创建完成后，请告诉我 Secret 名称，我会在 deployment 配置中添加引用"

#### Scenario: AI 添加业务 Secret 引用

- **WHEN** 用户告知 Secret 名称为 order-service-stripe-secret
- **THEN** AI SHALL 在 deployment overlay 中添加对应的 envFrom.secretRef，方式与 Operator Secret 完全一致

#### Scenario: AI 不询问密码值

- **WHEN** AI 引导用户创建业务 Secret
- **THEN** AI MUST 不询问"API Key 的值是什么？"或任何密码内容
