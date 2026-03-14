## MODIFIED Requirements

### Requirement: runtime 字段定义

`runtime` 字段 SHALL 包含服务的运行时配置：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| language | string | 是 | 编程语言（go/java/node/python） |
| port | integer | 是 | 服务监听端口 |
| health_check | string | 否 | 健康检查路径，默认 `/healthz` |
| metrics | string | 否 | Prometheus 指标路径，默认 `/metrics` |
| slow_start | boolean | 否 | 是否为慢启动服务，默认 `false`。为 true 时 AI 生成 startupProbe |
| migration_path | string | 否 | migration 文件目录路径（相对代码仓库根目录）。有值时 AI 在 deployment 中注入 Flyway init container，无值时不注入 |

#### Scenario: 有 migration_path 的 .devops.yaml

- **WHEN** 服务使用 DB migration
- **THEN** .devops.yaml 的 runtime 字段 SHALL 包含：
  ```yaml
  runtime:
    language: go
    port: 8080
    migration_path: db/migration
  ```

#### Scenario: 无 migration_path（不使用 migration）

- **WHEN** 服务不使用 DB migration
- **THEN** runtime 字段 SHALL 不包含 migration_path，deployment 中不注入 init container

#### Scenario: runtime 字段省略 health_check

- **WHEN** .devops.yaml 中 runtime 未指定 health_check
- **THEN** AI 生成 deployment.yaml 时 SHALL 使用默认值 `/healthz`

#### Scenario: 慢启动服务（如 Java）

- **WHEN** .devops.yaml 中 runtime.slow_start=true
- **THEN** AI 生成 base/deployment.yaml 时 SHALL 额外包含 startupProbe（httpGet health_check 路径，failureThreshold=30，periodSeconds=10），防止启动期间被 livenessProbe 杀掉

#### Scenario: AI 根据语言推荐 slow_start

- **WHEN** .devops.yaml 中 runtime.language=java 且未设置 slow_start
- **THEN** AI SHALL 提示"Java 服务通常启动较慢，建议设置 slow_start: true 以启用 startupProbe，是否添加？"
