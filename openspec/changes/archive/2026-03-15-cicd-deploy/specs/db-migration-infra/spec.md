## ADDED Requirements

### Requirement: Flyway init container 模板

平台 SHALL 提供标准的 Flyway CLI init container 配置模板。当服务的 .devops.yaml 包含 `runtime.migration_path` 时，AI 生成 deployment.yaml SHALL 在 base 中包含此 init container。

#### Scenario: 生成包含 init container 的 deployment

- **WHEN** AI 为服务生成 base/deployment.yaml，且 .devops.yaml 中 `runtime.migration_path` 为 `db/migration`
- **THEN** deployment.yaml SHALL 包含 init container：
  ```yaml
  initContainers:
    - name: db-migrate
      image: flyway/flyway:10
      args: ["migrate"]
      env:
        - name: MYSQL_HOST
          valueFrom:
            secretKeyRef:
              name: {instance-name}-secret
              key: MYSQL_HOST
        - name: MYSQL_PORT
          valueFrom:
            secretKeyRef:
              name: {instance-name}-secret
              key: MYSQL_PORT
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: {instance-name}-secret
              key: MYSQL_DATABASE
        - name: FLYWAY_URL
          value: "jdbc:mysql://$(MYSQL_HOST):$(MYSQL_PORT)/$(MYSQL_DATABASE)"
        - name: FLYWAY_USER
          valueFrom:
            secretKeyRef:
              name: {instance-name}-secret
              key: MYSQL_USER
        - name: FLYWAY_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {instance-name}-secret
              key: MYSQL_PASSWORD
        - name: FLYWAY_LOCATIONS
          value: "filesystem:/migrations"
      volumeMounts:
        - name: migrations
          mountPath: /migrations
  ```
  MYSQL_HOST/PORT/DATABASE 先从 Secret 注入为环境变量，FLYWAY_URL 通过 K8s `$(VAR)` 语法引用。

#### Scenario: 无 migration_path 时不生成 init container

- **WHEN** AI 为服务生成 base/deployment.yaml，且 .devops.yaml 不包含 `runtime.migration_path`
- **THEN** deployment.yaml SHALL 不包含任何 init container

#### Scenario: 无 MySQL owner 依赖时不生成 init container

- **WHEN** .devops.yaml 包含 `runtime.migration_path` 但 dependencies 中无 mysql role=owner
- **THEN** AI SHALL 警告"声明了 migration_path 但没有 MySQL owner 依赖，init container 无法获取数据库连接信息。请先添加 MySQL 依赖。"

---

### Requirement: Forward-only migration 策略

平台 SHALL 采用 forward-only migration 策略，不支持 DOWN migration。所有 schema 变更通过新的 UP migration 完成。

#### Scenario: 开发者询问如何回退 schema

- **WHEN** 开发者问"怎么回退数据库变更"
- **THEN** AI SHALL 解释 forward-only 策略："平台不支持 DOWN migration。如需撤销 schema 变更，请创建新的 migration 文件来反向操作（如 V5__revert_add_status.sql）。建议使用 expand-contract 模式，先添加新列，确认稳定后再清理旧列。"

---

### Requirement: Migration 文件约定

migration 文件 SHALL 遵循 Flyway 命名规范：`V{version}__{description}.sql`（版本号 + 双下划线 + 描述）。

#### Scenario: 文件命名示例

- **WHEN** 开发者需要添加 migration
- **THEN** 文件 SHALL 命名为如 `V1__create_orders_table.sql`、`V2__add_status_column.sql`，放在 `runtime.migration_path` 指定的目录下

#### Scenario: 命名不符合规范

- **WHEN** Flyway init container 执行时发现文件名不符合 `V{version}__{description}.sql` 格式
- **THEN** Flyway SHALL 报错并拒绝执行，Pod 启动失败，ArgoCD 标记为 degraded
