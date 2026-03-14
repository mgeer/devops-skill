## ADDED Requirements

### Requirement: 三层目录结构

配置仓库 SHALL 采用三层目录结构：infrastructure（平台基础设施）、resources（逻辑资源）、services（业务服务）。每层职责明确，不允许跨层放置文件。

- `infrastructure/`：Helm chart，平台团队管理，包含 Operators、监控栈、Ingress
- `resources/`：Kustomize overlay，业务团队通过 AI 管理，包含 Kafka topic、MySQL 实例、Redis 实例
- `services/`：Kustomize overlay，业务团队通过 AI 管理，包含服务部署配置

#### Scenario: 配置仓库初始化后的顶层目录

- **WHEN** 配置仓库初始化完成
- **THEN** 仓库根目录 SHALL 包含以下顶层条目：`platform-inventory.yaml`、`infrastructure/`、`resources/`、`services/`、`argocd/`

#### Scenario: 文件放置在错误的层

- **WHEN** AI 需要创建一个 Kafka topic 的 YAML 文件
- **THEN** 文件 SHALL 放在 `resources/{domain}/kafka/` 下，不得放在 `infrastructure/` 或 `services/` 下

---

### Requirement: 按业务域组织

resources 和 services 层 SHALL 按业务域（domain）组织子目录。domain 名称 MUST 与 platform-inventory.yaml 中定义的域名一致。

#### Scenario: 创建属于 trade 域的服务

- **WHEN** AI 创建一个 domain=trade 的服务 order-service
- **THEN** 服务目录 SHALL 位于 `services/trade/order-service/`

#### Scenario: 创建属于 trade 域的 MySQL 实例

- **WHEN** AI 创建一个属于 trade 域的 MySQL 实例 order-db
- **THEN** 资源目录 SHALL 位于 `resources/trade/mysql/order-db/`

#### Scenario: 使用未定义的域名

- **WHEN** AI 尝试在 `services/payment/` 下创建服务，但 platform-inventory.yaml 中没有 payment 域
- **THEN** AI SHALL 拒绝操作并提示"域 payment 未在 platform-inventory.yaml 中定义，请联系平台团队添加"

---

### Requirement: 路径公式

AI 生成配置文件时 SHALL 使用以下固定路径公式，不得自行发明路径：

| 资源类型 | 路径模板 |
|---------|---------|
| 服务 base | `services/{domain}/{service}/base/` |
| 服务 overlay | `services/{domain}/{service}/overlays/{env}/` |
| 资源 base | `resources/{domain}/{type}/{name}/base/` |
| 资源 overlay | `resources/{domain}/{type}/{name}/overlays/{env}/` |
| 平台基础设施 | `infrastructure/{category}/{component}/` |

#### Scenario: AI 生成服务的 dev overlay 路径

- **WHEN** AI 需要为 trade 域的 order-service 生成 dev 环境的 overlay
- **THEN** 路径 SHALL 为 `services/trade/order-service/overlays/dev/kustomization.yaml`

#### Scenario: AI 生成 Kafka topic 的 base 路径

- **WHEN** AI 需要为 trade 域的 order-events topic 创建 base 配置
- **THEN** 路径 SHALL 为 `resources/trade/kafka/order-events/base/topic.yaml`

---

### Requirement: services 目录结构

每个服务目录 SHALL 包含 base/ 和 overlays/ 两个子目录。base/ 包含环境无关的完整配置，overlays/ 按环境分子目录。

#### Scenario: 新建服务的完整目录结构

- **WHEN** AI 创建一个新服务 order-service（domain=trade）
- **THEN** SHALL 生成以下目录结构：
  ```
  services/trade/order-service/
  ├── base/
  │   ├── deployment.yaml
  │   ├── service.yaml
  │   ├── ingress.yaml
  │   └── kustomization.yaml
  └── overlays/
      ├── dev/
      │   └── kustomization.yaml
      ├── test/
      │   └── kustomization.yaml
      ├── staging/
      │   └── kustomization.yaml
      └── prod/
          └── kustomization.yaml
  ```

#### Scenario: 缺少某个环境的 overlay 目录

- **WHEN** 服务目录中缺少 `overlays/staging/` 目录
- **THEN** ApplicationSet 不会为该服务生成 staging 环境的 Application（服务不会部署到 staging），且 `kustomize build` 不受影响（不会报错）

---

### Requirement: resources 目录结构

每个逻辑资源 SHALL 包含 base/ 和 overlays/ 两个子目录，结构与 services 一致。

#### Scenario: 新建 MySQL 实例的完整目录结构

- **WHEN** AI 创建一个 MySQL 实例 order-db（domain=trade）
- **THEN** SHALL 生成以下目录结构：
  ```
  resources/trade/mysql/order-db/
  ├── base/
  │   └── instance.yaml
  └── overlays/
      ├── dev/
      │   └── kustomization.yaml
      ├── test/
      │   └── kustomization.yaml
      ├── staging/
      │   └── kustomization.yaml
      └── prod/
          └── kustomization.yaml
  ```

---

### Requirement: infrastructure 目录结构

infrastructure 层 SHALL 按类别（category）和组件（component）组织。每个组件是一个独立目录，包含 Helm release 定义。

#### Scenario: Operator 的目录结构

- **WHEN** 平台团队需要部署 Strimzi Kafka Operator
- **THEN** 配置 SHALL 位于 `infrastructure/operators/strimzi-kafka/helmrelease.yaml`

#### Scenario: AI 尝试修改 infrastructure 目录

- **WHEN** AI 需要修改 `infrastructure/` 下的任何文件
- **THEN** AI SHALL 生成变更内容但 MUST 通过 MR 提交，MR 的 reviewer MUST 包含平台团队成员
