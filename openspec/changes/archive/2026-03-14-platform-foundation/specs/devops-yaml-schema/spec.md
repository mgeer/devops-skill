## ADDED Requirements

### Requirement: 文件位置与格式

每个服务的代码仓库根目录 SHALL 包含一个 `.devops.yaml` 文件。文件格式为 YAML，包含四个顶层字段：`service`、`gitops`、`runtime`、`dependencies`。

#### Scenario: 新服务需要 .devops.yaml

- **WHEN** 开发者通过 `/devops` 创建新服务
- **THEN** AI SHALL 在代码仓库根目录生成 `.devops.yaml` 文件

#### Scenario: .devops.yaml 缺失

- **WHEN** AI 读取代码仓库时发现根目录没有 `.devops.yaml`
- **THEN** AI SHALL 提示"当前仓库未接入 DevOps 平台，是否需要创建 .devops.yaml？"

---

### Requirement: service 字段定义

`service` 字段 SHALL 包含服务的身份信息，所有子字段均为必填：

| 字段 | 类型 | 说明 | 校验规则 |
|------|------|------|---------|
| name | string | 服务名 | 符合命名规范 `^[a-z][a-z0-9-]{1,39}$` |
| domain | string | 业务域 | MUST 在 platform-inventory.yaml 的 domains 中存在 |
| team | string | 所属团队 | MUST 与 domain 对应的 team 一致 |
| owner | string | 负责人 | 非空字符串 |

#### Scenario: service 字段完整示例

- **WHEN** AI 为 trade 域的 order-service 生成 .devops.yaml
- **THEN** service 和 gitops 字段 SHALL 为：
  ```yaml
  service:
    name: order-service
    domain: trade
    team: trade-team
    owner: zhangsan

  gitops:
    repo: https://gitlab.company.com/infra/gitops-repo
    path: services/trade/order-service
  ```

#### Scenario: domain 不存在于 platform-inventory

- **WHEN** .devops.yaml 中 domain 为 payment，但 platform-inventory.yaml 中无此域
- **THEN** AI SHALL 报错"域 payment 未在平台清单中定义"并拒绝继续操作

---

### Requirement: gitops 字段定义

`gitops` 字段 SHALL 包含服务在配置仓库中的位置信息，所有子字段均为必填：

| 字段 | 类型 | 说明 | 来源 |
|------|------|------|------|
| repo | string | gitops 配置仓库地址 | 初始化时从 platform-spec.md 自动填充 |
| path | string | 服务在配置仓库中的路径 | 按命名规范自动生成：`services/{domain}/{service}` |

#### Scenario: gitops 字段完整示例

- **WHEN** AI 为 trade 域的 order-service 生成 .devops.yaml
- **THEN** gitops 字段 SHALL 为：
  ```yaml
  gitops:
    repo: https://gitlab.company.com/infra/gitops-repo
    path: services/trade/order-service
  ```

#### Scenario: 初始化时自动填充 gitops 字段

- **WHEN** AI 引导开发者初始化 .devops.yaml
- **THEN** AI SHALL 从 platform-spec.md 读取 gitops repo 地址自动填充 `gitops.repo`，按 `services/{domain}/{service}` 自动生成 `gitops.path`，展示给开发者确认

#### Scenario: gitops.path 与命名规范不一致

- **WHEN** .devops.yaml 中 `gitops.path` 为 `services/trade/order-svc`，但 `service.name` 为 `order-service`
- **THEN** AI SHALL 警告"gitops.path 与服务名不一致，预期为 services/trade/order-service，确认使用当前值？"

---

### Requirement: runtime 字段定义

`runtime` 字段 SHALL 包含服务的运行时配置：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| language | string | 是 | 编程语言（go/java/node/python） |
| port | integer | 是 | 服务监听端口 |
| health_check | string | 否 | 健康检查路径，默认 `/healthz` |
| metrics | string | 否 | Prometheus 指标路径，默认 `/metrics` |
| slow_start | boolean | 否 | 是否为慢启动服务，默认 `false`。为 true 时 AI 生成 startupProbe |

#### Scenario: runtime 字段省略 health_check

- **WHEN** .devops.yaml 中 runtime 未指定 health_check
- **THEN** AI 生成 deployment.yaml 时 SHALL 使用默认值 `/healthz`

#### Scenario: 慢启动服务（如 Java）

- **WHEN** .devops.yaml 中 runtime.slow_start=true
- **THEN** AI 生成 base/deployment.yaml 时 SHALL 额外包含 startupProbe（httpGet health_check 路径，failureThreshold=30，periodSeconds=10），防止启动期间被 livenessProbe 杀掉

#### Scenario: AI 根据语言推荐 slow_start

- **WHEN** .devops.yaml 中 runtime.language=java 且未设置 slow_start
- **THEN** AI SHALL 提示"Java 服务通常启动较慢，建议设置 slow_start: true 以启用 startupProbe，是否添加？"

---

### Requirement: dependencies 字段定义

`dependencies` 字段 SHALL 为数组，每个元素声明服务对一个资源的依赖：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| name | string | 是 | 资源名称，MUST 符合命名规范 |
| type | string | 是 | 资源类型：`mysql` / `redis` / `kafka-topic` |
| role | string | 是 | 依赖角色：`owner` / `producer` / `consumer` |

role 的含义：
- `owner`：该服务创建并拥有此资源（MySQL/Redis 使用）
- `producer`：该服务是此 Kafka topic 的生产者，同时拥有此 topic
- `consumer`：该服务消费此资源，资源由其他服务拥有

#### Scenario: 声明 MySQL 依赖（owner）

- **WHEN** 服务需要自己的 MySQL 数据库
- **THEN** dependencies 中 SHALL 包含：
  ```yaml
  - name: order-db
    type: mysql
    role: owner
  ```

#### Scenario: 声明 Kafka 消费依赖（consumer）

- **WHEN** 服务需要消费其他服务产生的 Kafka topic user-events
- **THEN** dependencies 中 SHALL 包含：
  ```yaml
  - name: user-events
    type: kafka-topic
    role: consumer
  ```

#### Scenario: 同一资源多个 owner

- **WHEN** 两个服务的 .devops.yaml 都对同一个资源（如 order-db）声明了 role=owner
- **THEN** AI SHALL 检测到冲突并报错"资源 order-db 已由服务 X 拥有，不能重复声明 owner"

---

### Requirement: .devops.yaml 作为持续的声明式意图源

.devops.yaml SHALL 作为服务 DevOps 意图的持续声明源（不是一次性输入）。当服务的依赖、团队等信息发生变更时，开发者 MUST 先更新 .devops.yaml，再通过 `/devops` 同步到配置仓库。

#### Scenario: 服务新增依赖

- **WHEN** 开发者在 .devops.yaml 中新增一个 Redis 依赖并运行 `/devops`
- **THEN** AI SHALL 对比配置仓库现状，检测到新增依赖，生成 `resources/{domain}/redis/{name}/` 目录和对应的配置文件，并创建 MR

#### Scenario: .devops.yaml 变更未同步

- **WHEN** 代码仓库 CI 检测到 .devops.yaml 文件有变更
- **THEN** CI SHALL 输出提示信息"检测到 .devops.yaml 变更，请运行 /devops 同步到配置仓库"（提示不阻塞 CI）

#### Scenario: AI 读取时发现漂移

- **WHEN** AI 读取 .devops.yaml 时发现其中声明的依赖与配置仓库现状不一致
- **THEN** AI SHALL 列出差异并询问"是否需要同步以下变更到配置仓库？"
