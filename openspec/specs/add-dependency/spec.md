## ADDED Requirements

### Requirement: add-dependency 前置条件

AI 执行 add-dependency 前 SHALL 检查服务已接入平台（.devops.yaml 存在且有效）。

#### Scenario: 服务未接入

- **WHEN** 开发者请求添加依赖，但当前仓库没有 .devops.yaml
- **THEN** AI SHALL 提示"当前仓库未接入 DevOps 平台，请先运行 /devops 初始化"

#### Scenario: .devops.yaml 存在

- **WHEN** 开发者请求添加依赖，.devops.yaml 存在
- **THEN** AI SHALL 读取 .devops.yaml，确认服务名和域信息，提示"为 {service-name} 添加依赖"

---

### Requirement: 依赖类型和角色选择

AI SHALL 引导用户选择依赖类型和角色。类型 MUST 在 platform-inventory.yaml 的 middleware 中存在且 available=true。

#### Scenario: 引导选择依赖类型

- **WHEN** 用户请求添加依赖但未指定类型
- **THEN** AI SHALL 展示可用的中间件类型列表（从 platform-inventory.yaml 读取），让用户选择

#### Scenario: 中间件不可用

- **WHEN** 用户请求添加的中间件类型在 platform-inventory.yaml 中 available=false 或不存在
- **THEN** AI SHALL 提示"该中间件类型尚未在平台上线，请联系平台团队"

#### Scenario: MySQL/Redis 角色选择

- **WHEN** 用户选择添加 MySQL 或 Redis 依赖
- **THEN** AI SHALL 询问"您是要创建新实例（owner）还是引用已有实例（consumer）？"

#### Scenario: Kafka 角色选择

- **WHEN** 用户选择添加 Kafka topic 依赖
- **THEN** AI SHALL 询问"您是生产者（producer，创建新 topic）还是消费者（consumer，消费已有 topic）？"

---

### Requirement: owner/producer 操作 — 创建新资源

角色为 owner 或 producer 时，AI SHALL 按命名规范创建新资源，检查冲突后生成配置仓库文件。

#### Scenario: 创建 MySQL 实例

- **WHEN** 用户为 order-service 添加 MySQL 依赖，角色为 owner
- **THEN** AI SHALL：
  1. 按命名规范生成资源名 `order-service-db`（可让用户修改）
  2. 检查 `resources/trade/mysql/order-service-db/` 是否已存在
  3. 创建资源目录（base/instance.yaml + overlays/）
  4. 在服务的 deployment overlay 中添加 `envFrom: secretRef: order-service-db-secret`
  5. 更新 .devops.yaml 的 dependencies

#### Scenario: 创建 Kafka topic

- **WHEN** 用户为 order-service 添加 Kafka topic 依赖，角色为 producer
- **THEN** AI SHALL：
  1. 按命名规范引导 topic 名称 `trade.order-service.{event}`，让用户指定 event 部分
  2. 检查 `resources/trade/kafka/{topic-name}/` 是否已存在
  3. 创建 topic 目录（base/topic.yaml + overlays/）
  4. 在服务的 deployment overlay 中添加 `KAFKA_BOOTSTRAP` 环境变量
  5. 更新 .devops.yaml 的 dependencies

#### Scenario: 资源名冲突

- **WHEN** AI 创建资源时发现同名资源已存在
- **THEN** AI SHALL 报错"资源 {name} 已存在于配置仓库，如果您要引用已有资源，请选择 consumer 角色"

---

### Requirement: consumer 操作 — 引用已有资源

角色为 consumer 时，AI SHALL 验证目标资源存在，只添加环境变量引用，不创建资源。

#### Scenario: 消费已存在的 MySQL 实例

- **WHEN** 用户为服务添加 MySQL consumer 依赖，指定实例名 order-service-db
- **THEN** AI SHALL：
  1. 验证 `resources/trade/mysql/order-service-db/` 在配置仓库中存在
  2. 在服务的 deployment overlay 中添加 `envFrom: secretRef: order-service-db-secret`
  3. 更新 .devops.yaml 的 dependencies（role=consumer）

#### Scenario: 消费已存在的 Kafka topic

- **WHEN** 用户为服务添加 Kafka topic consumer 依赖，指定 topic 名 trade.order-service.created
- **THEN** AI SHALL：
  1. 验证 `resources/trade/kafka/trade.order-service.created/` 在配置仓库中存在
  2. 在服务的 deployment overlay 中添加 `KAFKA_BOOTSTRAP` 环境变量
  3. 更新 .devops.yaml 的 dependencies（role=consumer）

#### Scenario: 目标资源不存在

- **WHEN** 用户声明 consumer 依赖一个不存在的资源
- **THEN** AI SHALL 报错"资源 {name} 在配置仓库中不存在，请确认名称或联系 owner 先创建"

#### Scenario: 跨域消费依赖

- **WHEN** user 域的 user-service 请求消费 trade 域的 order-events topic
- **THEN** AI SHALL 提示"这是一个跨域依赖（user → trade），确认添加？"，确认后正常处理。.devops.yaml 的 dependency 条目 MUST 包含 `domain: trade` 字段

#### Scenario: 跨域 consumer 定位资源

- **WHEN** 用户声明 consumer 依赖，且资源不在当前服务的域中
- **THEN** AI SHALL 询问"该资源属于哪个域？"（或从用户指定的资源名推断域），定位到 `resources/{target-domain}/{type}/{name}/` 验证资源存在

---

### Requirement: 变更同步到配置仓库

添加依赖后，AI SHALL 将所有变更同步到配置仓库并创建 MR。

#### Scenario: 同步变更

- **WHEN** 用户确认依赖配置
- **THEN** AI SHALL 通过 MCP 在配置仓库中执行变更，创建 MR。MR 描述包含：操作发起人、"为 {service} 添加 {type} 依赖 {name}"意图、变更文件列表

#### Scenario: 同时更新 .devops.yaml

- **WHEN** 依赖添加完成
- **THEN** AI SHALL 同时更新代码仓库中的 .devops.yaml，在 dependencies 数组中新增对应条目

#### Scenario: 资源规格选择（owner 创建时）

- **WHEN** AI 创建新的中间件资源实例
- **THEN** AI SHALL 使用 resource-quota capability 定义的默认规格，不在 add-dependency 流程中单独询问规格（中间件资源使用 Operator 默认值，应用服务规格在 init-service 时已选择）

---

### Requirement: remove-dependency — 移除已有依赖

AI SHALL 支持移除服务的已有依赖。移除操作根据角色不同处理方式不同。

#### Scenario: 移除 consumer 依赖

- **WHEN** 用户请求移除 notification-service 对 order-events 的 consumer 依赖
- **THEN** AI SHALL：
  1. 从 .devops.yaml 的 dependencies 中删除对应条目
  2. 从 deployment overlay 中移除相关环境变量引用
  3. 创建 MR 同步配置仓库变更
  4. 不删除资源本身（资源由 owner 管理）

#### Scenario: 移除 owner 依赖 — 无消费方

- **WHEN** 用户请求移除 order-service 对 order-db 的 owner 依赖，且无其他服务引用 order-db
- **THEN** AI SHALL 确认"移除 owner 依赖将同时删除 MySQL 实例 order-db，确认？"，确认后：
  1. 从 .devops.yaml 的 dependencies 中删除对应条目
  2. 从 deployment overlay 中移除 envFrom secretRef
  3. 删除 `resources/{domain}/mysql/order-db/` 目录
  4. 创建 MR 同步所有变更

#### Scenario: 移除 owner 依赖 — 有消费方

- **WHEN** 用户请求移除 order-service 对 order-events 的 producer 依赖，但有其他服务消费该 topic
- **THEN** AI SHALL 采用"尽力检查 + 不确定就问"策略确认消费方情况，有消费方时阻止删除并提示"请先处理消费方或转移所有权"

#### Scenario: 意图识别

- **WHEN** 用户说"我不需要 Redis 了"或"移除 order-cache 依赖"
- **THEN** AI SHALL 识别为 remove-dependency 意图，从 .devops.yaml 中查找对应依赖条目
