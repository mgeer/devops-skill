## MODIFIED Requirements

### Requirement: dependencies 字段定义

`dependencies` 字段 SHALL 为数组，每个元素声明服务对一个资源的依赖：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| name | string | 是 | 资源名称，MUST 符合命名规范 |
| type | string | 是 | 资源类型：`mysql` / `redis` / `kafka-topic` |
| role | string | 是 | 依赖角色：`owner` / `producer` / `consumer` |
| domain | string | 跨域时必填 | 资源所属域。同域时可省略（默认为 service.domain），跨域引用时 MUST 填写 |

role 的含义：
- `owner`：该服务创建并拥有此资源（MySQL/Redis 使用）
- `producer`：该服务是此 Kafka topic 的生产者，同时拥有此 topic
- `consumer`：该服务消费此资源，资源由其他服务拥有

#### Scenario: 同域 consumer 依赖（domain 可省略）

- **WHEN** trade 域的 analytics-service 消费同域的 order-events topic
- **THEN** dependencies 中 SHALL 为：
  ```yaml
  - name: order-events
    type: kafka-topic
    role: consumer
  ```
  domain 省略，默认与 service.domain 一致

#### Scenario: 跨域 consumer 依赖（domain 必填）

- **WHEN** user 域的 notification-service 消费 trade 域的 order-events topic
- **THEN** dependencies 中 SHALL 为：
  ```yaml
  - name: order-events
    type: kafka-topic
    role: consumer
    domain: trade
  ```

#### Scenario: AI 定位跨域资源路径

- **WHEN** AI 处理跨域 consumer 依赖，domain 为 trade
- **THEN** AI SHALL 在 `resources/trade/` 下查找目标资源，而非在当前服务的域下查找

#### Scenario: 声明 MySQL 依赖（owner）

- **WHEN** 服务需要自己的 MySQL 数据库
- **THEN** dependencies 中 SHALL 包含：
  ```yaml
  - name: order-db
    type: mysql
    role: owner
  ```

#### Scenario: 同一资源多个 owner

- **WHEN** 两个服务的 .devops.yaml 都对同一个资源（如 order-db）声明了 role=owner
- **THEN** AI SHALL 检测到冲突并报错"资源 order-db 已由服务 X 拥有，不能重复声明 owner"
