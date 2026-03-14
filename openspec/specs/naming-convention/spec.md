## ADDED Requirements

### Requirement: 服务命名规范

服务名 SHALL 遵循以下规则：
- 小写字母开头
- 仅包含小写字母、数字、连字符
- 长度 2-40 字符
- 校验正则：`^[a-z][a-z0-9-]{1,39}$`

#### Scenario: 合法服务名

- **WHEN** 开发者指定服务名为 `order-service`
- **THEN** AI SHALL 接受该名称（匹配正则）

#### Scenario: 不合法服务名 — 大写字母

- **WHEN** 开发者指定服务名为 `OrderService`
- **THEN** AI SHALL 拒绝并建议"服务名必须为小写，建议使用 order-service"

#### Scenario: 不合法服务名 — 下划线

- **WHEN** 开发者指定服务名为 `order_service`
- **THEN** AI SHALL 拒绝并建议"服务名不允许下划线，建议使用 order-service"

---

### Requirement: namespace 命名规范

namespace SHALL 按 `{env}-{domain}` 格式命名，其中 env 为 dev/test/staging/prod，domain 为 platform-inventory.yaml 中定义的域名。

#### Scenario: 生成 namespace 名称

- **WHEN** AI 需要为 trade 域的 prod 环境生成 namespace
- **THEN** namespace SHALL 为 `prod-trade`

---

### Requirement: 中间件资源命名规范

中间件资源名 SHALL 按以下模板命名：

| 资源类型 | 模板 | 示例 |
|---------|------|------|
| MySQL 实例 | `{service}-db` | `order-service-db` |
| Redis 实例 | `{service}-cache` | `order-service-cache` |
| Kafka topic | `{domain}.{service}.{event}` | `trade.order-service.created` |

#### Scenario: 创建 MySQL 实例名称

- **WHEN** AI 为 order-service 创建 MySQL 实例
- **THEN** 实例名 SHALL 为 `order-service-db`

#### Scenario: 创建 Kafka topic 名称

- **WHEN** AI 为 trade 域的 order-service 创建 order-created 事件的 topic
- **THEN** topic 名称 SHALL 为 `trade.order-service.order-created`

#### Scenario: 自定义资源名

- **WHEN** 开发者希望 MySQL 实例不叫 `order-service-db` 而叫 `order-legacy-db`
- **THEN** AI SHALL 提示"默认命名为 order-service-db，确认使用 order-legacy-db？"，开发者确认后允许使用

---

### Requirement: Docker 镜像命名规范

Docker 镜像地址 SHALL 按 `{registry}/{domain}/{service}:{tag}` 格式，其中 tag 为 git commit SHA 的前 8 位。

#### Scenario: 生成镜像地址

- **WHEN** CI 为 trade 域的 order-service 构建镜像，commit SHA 为 a1b2c3d4e5f6
- **THEN** 镜像地址 SHALL 为 `harbor.company.com/trade/order-service:a1b2c3d4`

---

### Requirement: Label 规范

所有 AI 生成的 K8s 资源 SHALL 包含以下标准 label：

| Label | 值 | 用途 |
|-------|---|------|
| app | `{service}` | 标识所属服务 |
| domain | `{domain}` | 标识所属业务域 |
| team | `{team}` | 标识所属团队 |
| env | `{env}` | 标识所属环境 |
| managed-by | `devops-skill` | 标识由平台管理 |

#### Scenario: Deployment 的 label

- **WHEN** AI 生成 order-service 的 Deployment
- **THEN** metadata.labels SHALL 包含 `app: order-service`、`domain: trade`、`team: trade-team`、`managed-by: devops-skill`

#### Scenario: env label 由 overlay 设置

- **WHEN** AI 生成 base/deployment.yaml
- **THEN** base 中不得包含 `env` label；`env` label SHALL 在 overlay 中通过 patch 添加

---

### Requirement: 命名冲突检测

AI 创建任何资源前 SHALL 检查配置仓库中是否已存在同名路径。路径即唯一标识。

#### Scenario: 服务名冲突

- **WHEN** AI 创建 order-service，但 `services/trade/order-service/` 目录已存在
- **THEN** AI SHALL 报错"服务 order-service 在 trade 域中已存在"并拒绝创建

#### Scenario: 跨域同名服务

- **WHEN** trade 域已有 order-service，user 域也要创建 order-service
- **THEN** AI SHALL 允许创建（路径为 `services/user/order-service/`，不冲突），但提示"注意：trade 域也有同名服务 order-service"

#### Scenario: 资源名冲突

- **WHEN** AI 创建 Kafka topic trade.order-service.created，但 `resources/trade/kafka/order-events/` 目录已存在
- **THEN** AI SHALL 报错"该 Kafka topic 已存在"并拒绝创建

---

### Requirement: 重命名策略

服务或资源的重命名 SHALL 按"创建新 → 迁移 → 删除旧"三步执行，不支持原地重命名。原因：名称嵌入在配置仓库路径、K8s 资源 metadata.name、labels、ArgoCD Application 名称等多处，原地重命名无法保证原子性，AI 操作容易遗漏。

#### Scenario: 服务重命名

- **WHEN** 开发者请求将 order-service 重命名为 order-svc
- **THEN** AI SHALL 提示"重命名将按以下步骤执行：1) 创建 order-svc 的完整配置（新目录）；2) 验证新服务部署正常；3) 删除旧的 order-service 配置。确认继续？"，不得直接修改现有目录名

#### Scenario: 资源重命名

- **WHEN** 开发者请求将 MySQL 实例 order-db 重命名为 order-main-db
- **THEN** AI SHALL 检查是否有其他服务依赖 order-db，有依赖时 MUST 先提示更新依赖方，然后按"创建新 → 迁移数据（手动） → 删除旧"三步引导

#### Scenario: 服务迁移域

- **WHEN** 开发者请求将 order-service 从 trade 域迁移到 commerce 域
- **THEN** AI SHALL 按重命名流程处理（域变更 = 路径变更 = namespace 变更），等同于创建新 + 删除旧
