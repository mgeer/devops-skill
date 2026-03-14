## ADDED Requirements

### Requirement: 文件位置与定位

platform-inventory.yaml SHALL 放在配置仓库根目录，作为 AI 的"平台能力地图"。AI 在执行任何操作前 SHALL 先读取此文件获取平台上下文。

#### Scenario: AI 执行操作前读取平台清单

- **WHEN** 开发者通过 `/devops` 请求创建服务
- **THEN** AI SHALL 先读取 platform-inventory.yaml，获取可用的域、中间件、集群信息，再开始操作

#### Scenario: platform-inventory.yaml 缺失

- **WHEN** 配置仓库根目录没有 platform-inventory.yaml
- **THEN** AI SHALL 报错"配置仓库缺少 platform-inventory.yaml，请联系平台团队初始化"

---

### Requirement: clusters 字段定义

`clusters` 字段 SHALL 定义所有 K8s 集群及其承载的环境：

```yaml
clusters:
  - name: non-prod
    api_server: https://k8s-nonprod.company.com
    environments: [dev, test, staging]
  - name: prod
    api_server: https://k8s-prod.company.com
    environments: [prod]
```

每个集群 MUST 包含 `name`、`api_server`、`environments` 字段。`environments` 数组的值 MUST 在 `environments` 顶层字段中有对应定义。

#### Scenario: 查询某环境所在集群

- **WHEN** AI 需要确定 staging 环境部署到哪个集群
- **THEN** AI SHALL 从 clusters 中找到 environments 包含 staging 的集群（non-prod）

---

### Requirement: environments 字段定义

`environments` 字段 SHALL 定义每个环境的部署策略：

```yaml
environments:
  dev:    { cluster: non-prod, auto_deploy: true,  approval: none }
  test:   { cluster: non-prod, auto_deploy: false, approval: team }
  staging:{ cluster: non-prod, auto_deploy: false, approval: tech-lead }
  prod:   { cluster: prod,     auto_deploy: false, approval: tech-lead+sre }
```

| 子字段 | 类型 | 说明 |
|--------|------|------|
| cluster | string | 对应 clusters[].name |
| auto_deploy | boolean | CI 是否自动部署（true=CI 直推，false=走 MR） |
| approval | string | 审批要求 |

#### Scenario: AI 判断是否需要创建 MR

- **WHEN** AI 需要更新 test 环境的镜像 tag
- **THEN** AI SHALL 读取 environments.test.auto_deploy（false），创建 MR 而非直接推送

---

### Requirement: domains 字段定义

`domains` 字段 SHALL 定义所有业务域及其 namespace 映射：

```yaml
domains:
  - name: trade
    team: trade-team
    namespaces:
      dev: dev-trade
      test: test-trade
      staging: staging-trade
      prod: prod-trade
```

每个域 MUST 包含 `name`、`team`、`namespaces` 字段。`namespaces` MUST 覆盖所有已定义的环境。

#### Scenario: AI 查找服务的 namespace

- **WHEN** AI 需要确定 trade 域服务在 staging 环境的 namespace
- **THEN** AI SHALL 从 domains 中找到 name=trade 的域，取 namespaces.staging 值（staging-trade）

#### Scenario: 新增域

- **WHEN** 平台团队需要新增 payment 域
- **THEN** SHALL 在 domains 中添加 payment 条目（含 name、team、namespaces），并创建对应的 K8s namespace

---

### Requirement: naming 字段定义

`naming` 字段 SHALL 定义全平台的命名模板，AI 生成资源名称时 MUST 套用这些模板：

```yaml
naming:
  service: "{name}"
  namespace: "{env}-{domain}"
  mysql_instance: "{service}-db"
  redis_instance: "{service}-cache"
  kafka_topic: "{domain}.{service}.{event}"
  docker_image: "{registry}/{domain}/{service}:{git-sha-short}"
  label_app: "{service}"
  label_domain: "{domain}"
```

#### Scenario: AI 生成 Kafka topic 名称

- **WHEN** AI 为 trade 域的 order-service 创建 created 事件的 topic
- **THEN** topic 名称 SHALL 为 `trade.order-service.created`（套用 naming.kafka_topic 模板）

---

### Requirement: middleware 字段定义

`middleware` 字段 SHALL 声明平台支持的中间件类型及其可用状态：

```yaml
middleware:
  kafka:
    available: true
    operator: strimzi
    version: "0.38"
    cluster_name: kafka-cluster
    bootstrap: kafka-cluster-kafka-bootstrap.kafka.svc:9092
  mysql:
    available: true
    operator: oracle-mysql-operator
    version: "8.0"
  redis:
    available: true
    operator: redis-operator
    version: "7.0"
```

每个中间件 MUST 包含 `available`（boolean）和 `operator`（string）字段。

#### Scenario: 中间件可用

- **WHEN** 开发者请求创建 MySQL 实例，且 middleware.mysql.available=true
- **THEN** AI SHALL 继续创建流程，生成对应的 Operator CR YAML

#### Scenario: 中间件不可用

- **WHEN** 开发者请求创建 Elasticsearch 索引，但 middleware 中无 elasticsearch 定义或 available=false
- **THEN** AI SHALL 提示"Elasticsearch 尚未在平台上线，请联系平台团队"

---

### Requirement: observability 和 registry 字段定义

`observability` 字段 SHALL 声明可观测性栈的可用状态。`registry` 字段 SHALL 声明镜像仓库地址和项目命名规则。

#### Scenario: AI 生成镜像地址

- **WHEN** AI 为 trade 域的 order-service 生成镜像地址
- **THEN** SHALL 使用 `{registry.url}/{registry.project}/{service}` 即 `harbor.company.com/trade/order-service`

---

### Requirement: 平台团队维护

platform-inventory.yaml SHALL 仅由平台团队维护。配置仓库 MUST 通过 CODEOWNERS 保护此文件，变更需要平台团队成员审批。

#### Scenario: 非平台团队成员修改

- **WHEN** 业务团队成员提交的 MR 包含对 platform-inventory.yaml 的修改
- **THEN** MR SHALL 自动添加平台团队成员为 reviewer，且 MUST 获得平台团队审批才能合并

#### Scenario: 与集群状态不一致

- **WHEN** platform-inventory.yaml 声明 kafka.available=true，但集群中 Strimzi Operator 实际未部署
- **THEN** AI 生成的 Kafka topic CR 在 ArgoCD 同步时 SHALL 失败（大声失败），提示 CRD 不存在
