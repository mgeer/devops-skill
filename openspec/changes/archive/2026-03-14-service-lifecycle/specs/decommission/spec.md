## ADDED Requirements

### Requirement: decommission 前置条件

AI 执行 decommission 前 SHALL 确认服务已接入平台且用户明确表达下线意图。

#### Scenario: 确认下线意图

- **WHEN** 开发者说"我要下线 order-service"
- **THEN** AI SHALL 确认"确认要下线 order-service 吗？这将删除该服务在配置仓库中的所有配置文件"

#### Scenario: 服务未接入

- **WHEN** 开发者请求下线服务，但 .devops.yaml 不存在
- **THEN** AI SHALL 提示"当前仓库未接入 DevOps 平台，无法执行下线操作"

---

### Requirement: 依赖影响分析 — 尽力检查 + 不确定就问

AI SHALL 在执行下线前进行依赖影响分析。采用"尽力检查 + 不确定就问"策略：AI 利用配置仓库中可获取的信息尽力检查，无法确认时 MUST 询问用户，不得猜测。

**检查策略：**

| 资源类型 | AI 可检查的方式 | 不确定时 |
|---------|---------------|---------|
| MySQL/Redis | 搜索配置仓库所有 overlay 中的 `{instance-name}-secret` secretRef 引用 | 未找到引用但不确定 → 询问用户 |
| Kafka topic | 无法从配置仓库确认消费方（KAFKA_BOOTSTRAP 不含 topic 信息） | MUST 询问用户 |

#### Scenario: MySQL 依赖可确认无消费方

- **WHEN** AI 搜索配置仓库所有 `services/*/overlays/` 目录，未找到任何对 `order-db-secret` 的 secretRef 引用（除 order-service 自身外）
- **THEN** AI SHALL 报告"order-db 未被其他服务引用，可安全删除"

#### Scenario: MySQL 依赖发现消费方

- **WHEN** AI 搜索发现 `services/user/analytics-service/overlays/dev/kustomization.yaml` 中引用了 `order-db-secret`
- **THEN** AI SHALL 报告"order-db 被 analytics-service 引用，无法直接删除"

#### Scenario: Kafka topic 无法确认 — 询问用户

- **WHEN** order-service 拥有 Kafka topic order-events，AI 无法从配置仓库确认是否有消费方
- **THEN** AI SHALL 询问"无法自动确认 Kafka topic order-events 是否有其他服务在消费，请确认：该 topic 是否还有消费方？"

#### Scenario: 用户确认无消费方

- **WHEN** AI 询问后用户回答"没有消费方了"
- **THEN** AI SHALL 继续删除流程

#### Scenario: 用户确认有消费方

- **WHEN** AI 询问后用户回答"notification-service 还在消费"
- **THEN** AI SHALL 阻止删除该资源，提示"请先让 notification-service 移除依赖，或将资源所有权转移"

---

### Requirement: 有依赖时的处理策略

当服务拥有的资源有外部 consumer 时，AI SHALL 阻止删除该资源，并提供解决方案。

#### Scenario: 阻止删除有 consumer 的资源

- **WHEN** 开发者确认下线，但 order-events 有 consumer
- **THEN** AI SHALL 提示"以下资源有外部依赖，无法删除：\n- order-events (consumer: notification-service, analytics-service)\n请先让消费方移除依赖，或将资源所有权转移给其他服务"

#### Scenario: 跨域依赖通知

- **WHEN** 被阻止删除的资源的 consumer 来自其他域
- **THEN** AI SHALL 额外提示"消费方 {service} 属于 {domain} 域（团队：{team}），请联系对方团队协调"

#### Scenario: 所有权转移建议

- **WHEN** 资源有 consumer 且需要保留
- **THEN** AI SHALL 建议"可以将 {resource} 的所有权转移给 {consumer-service}（需修改双方的 .devops.yaml）"

---

### Requirement: 分步清理流程

AI SHALL 按以下顺序引导清理，每步独立确认：

1. 删除可安全删除的 owner 资源（逐个确认）
2. 删除服务配置目录（services/{domain}/{service}/）
3. 提示开发者手动处理代码仓库侧的清理

#### Scenario: 逐个确认资源删除

- **WHEN** order-service 拥有 order-db（可删除）和 order-cache（可删除）
- **THEN** AI SHALL 逐个确认："删除 MySQL 实例 order-db？"→ 确认 → "删除 Redis 实例 order-cache？"→ 确认

#### Scenario: 删除服务配置目录

- **WHEN** 所有可删除的资源已处理
- **THEN** AI SHALL 确认"将删除 services/trade/order-service/ 目录（包含 base 和所有 overlay），确认？"

#### Scenario: 创建删除 MR

- **WHEN** 用户确认所有删除操作
- **THEN** AI SHALL 通过 MCP 创建一个 MR，包含所有删除变更。MR 描述包含：操作发起人、"下线服务 {service}"意图、删除的文件列表、保留的资源（有依赖）。MR reviewer MUST 包含 Tech Lead（下线是高危操作，审批级别等同 staging/prod 推进）

#### Scenario: 提示手动清理

- **WHEN** 配置仓库 MR 创建完成
- **THEN** AI SHALL 展示待开发者手动处理的事项清单：
  1. 删除代码仓库中的 .devops.yaml
  2. 移除 .gitlab-ci.yml 中的配置仓库相关步骤
  3. 注意事项："MR 合并后 ArgoCD 将自动清理 dev 环境资源。test/staging/prod 环境需要手动触发 sync"
