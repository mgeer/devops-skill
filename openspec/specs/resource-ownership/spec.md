## ADDED Requirements

### Requirement: 资源所有权规则

每个逻辑资源（MySQL 实例、Redis 实例、Kafka topic）SHALL 有且只有一个 owner。所有权通过 .devops.yaml 中的 `role` 字段声明：

| 资源类型 | 所有者 | 说明 |
|---------|-------|------|
| MySQL 实例 | role=owner 的服务 | 创建者拥有，通常独占 |
| Redis 实例 | role=owner 的服务 | 创建者拥有，通常独占 |
| Kafka topic | role=producer 的服务 | 谁产生数据谁拥有 |

#### Scenario: MySQL 实例所有权

- **WHEN** order-service 的 .devops.yaml 声明 `{name: order-db, type: mysql, role: owner}`
- **THEN** order-db 的 owner 为 order-service，资源 YAML 的 `metadata.labels.owner` SHALL 为 `order-service`

#### Scenario: Kafka topic 所有权

- **WHEN** order-service 的 .devops.yaml 声明 `{name: order-events, type: kafka-topic, role: producer}`
- **THEN** order-events 的 owner 为 order-service

#### Scenario: 所有权冲突

- **WHEN** 两个服务都对同一资源声明 role=owner 或 role=producer
- **THEN** AI SHALL 检测到冲突并报错"资源 X 已由服务 Y 拥有，不能重复声明所有权"

---

### Requirement: 依赖引用机制

非 owner 的服务通过 .devops.yaml 的 `role=consumer` 声明对资源的引用。引用不创建资源，只表达"我使用这个资源"。

#### Scenario: 消费已存在的 Kafka topic

- **WHEN** notification-service 的 .devops.yaml 声明 `{name: order-events, type: kafka-topic, role: consumer}`
- **THEN** AI SHALL 验证 `resources/{domain}/kafka/order-events/` 目录已存在，不创建新资源，只在 notification-service 的 overlay 中添加 Kafka bootstrap 环境变量

#### Scenario: 消费不存在的资源

- **WHEN** 服务声明 consumer 依赖一个不存在的 Kafka topic
- **THEN** AI SHALL 报错"Kafka topic X 在配置仓库中不存在，请确认 topic 名称或联系 owner 先创建"

---

### Requirement: 依赖追踪

AI SHALL 能够构建完整的资源依赖图，追踪哪些服务依赖了哪些资源。

#### Scenario: 查看资源的所有依赖方

- **WHEN** 开发者询问"谁在用 order-events 这个 topic？"
- **THEN** AI SHALL 扫描所有服务的 .devops.yaml，列出所有声明了 `name: order-events` 依赖的服务及其角色（producer/consumer）

#### Scenario: 查看服务的所有依赖

- **WHEN** 开发者询问"order-service 依赖了什么？"
- **THEN** AI SHALL 读取 order-service 的 .devops.yaml，列出所有 dependencies 及其类型和角色

---

### Requirement: 删除保护

删除资源前 AI MUST 检查是否有其他服务依赖该资源。有依赖时 MUST 阻止删除。

#### Scenario: 删除无依赖的资源

- **WHEN** 开发者请求删除 Kafka topic order-events，且只有 order-service（owner）使用它
- **THEN** AI SHALL 确认"order-events 仅被 order-service（owner）使用，确认删除？"

#### Scenario: 删除有 consumer 的资源

- **WHEN** 开发者请求删除 Kafka topic order-events，但 notification-service 是其 consumer
- **THEN** AI SHALL 阻止并提示"无法删除 order-events，以下服务仍在消费：notification-service。请先移除这些依赖"

#### Scenario: 删除服务时检查其拥有的资源

- **WHEN** 开发者请求下线 order-service，该服务拥有 order-db（无其他依赖）和 order-events（有 consumer）
- **THEN** AI SHALL 提示"order-service 拥有以下资源：order-db（可安全删除）、order-events（有 consumer: notification-service，不可删除）。请先处理 order-events 的消费者"

---

### Requirement: 跨域依赖处理

服务 SHALL 允许依赖其他域的资源（跨域依赖），但 AI MUST 明确提示并要求确认。

#### Scenario: 跨域消费 Kafka topic

- **WHEN** user 域的 user-service 声明消费 trade 域的 order-events topic
- **THEN** AI SHALL 提示"这是一个跨域依赖（user → trade），确认添加？"，并在确认后在 overlay 中添加对应的环境变量

#### Scenario: 跨域依赖的 NetworkPolicy

- **WHEN** 跨域依赖被确认
- **THEN** AI SHALL 提示"跨域访问需要 NetworkPolicy 放通，将在 Change 5 中处理"（本 change 只记录依赖关系，不生成 NetworkPolicy）
