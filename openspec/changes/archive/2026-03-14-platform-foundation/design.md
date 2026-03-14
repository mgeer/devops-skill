## Context

公司从零构建基于 GitLab + ArgoCD 的 DevOps 平台，以 AI Skill（`/devops`）作为唯一交互界面。本 change 是"厚地基"——定义整个平台的运行规则，后续所有 change 在此框架内工作。

**当前状态：** 无统一规范，各服务接入方式不一致。

**核心约束：**
- 底层设计原则：**AI 操作不易出错**（所有架构决策的第一判断标准）
- 优先级：安全 > 准确 > 可追溯 > 体验（P0 > P1 > P2 > P3）
- AI 只生成 YAML 和创建 MR，不直接操作集群

**利益相关方：**
- 平台团队：维护 infrastructure 层和 platform-inventory.yaml
- 业务团队：通过 /devops skill 管理 services 和 resources 层
- SRE：审批生产环境变更和基础设施变更

---

## Goals / Non-Goals

**Goals:**

- 定义配置仓库三层结构（infrastructure / resources / services），按业务域组织，AI 可可靠地生成正确路径
- 定义 .devops.yaml 和 platform-inventory.yaml 的完整 schema，消除字段歧义
- 定义命名规范，覆盖所有资源类型，AI 可机械式套用不需判断
- 定义 Kustomize overlay 方案，明确 base 与 overlay 的内容边界
- 定义 GitOps 工作流联动（CI → 配置仓库 → ArgoCD → K8s），精确定义"CI 直推"的含义和安全边界
- 定义 ArgoCD ApplicationSet 自动发现规则和按环境区分的同步策略
- 定义 Day 0 平台初始化流程
- 定义 .devops.yaml 的精确定位（声明式意图源 vs 一次性输入）
- 定义 platform-inventory.yaml 的维护机制
- 产出 skill.md 骨架（核心原则 + AI 处理逻辑框架）

**Non-Goals:**

- 具体服务的创建/部署/下线 flow 设计（Change 2、3）
- Secret 管理方案（Change 2）
- CI/CD 流水线阶段定义（Change 3）
- 可观测性分层标准和告警规则（Change 4）
- NetworkPolicy 模板和备份策略（Change 5）
- 灰度发布和本地开发（Change 6）

---

## Decisions

### D1: 配置仓库目录结构 — 按业务域组织

```
gitops-repo/
├── platform-inventory.yaml
│
├── infrastructure/                    # 第 1 层：平台基础设施（Helm）
│   ├── operators/
│   │   ├── strimzi-kafka/
│   │   │   └── helmrelease.yaml
│   │   ├── mysql-operator/
│   │   │   └── helmrelease.yaml
│   │   └── redis-operator/
│   │       └── helmrelease.yaml
│   ├── monitoring/
│   │   ├── prometheus/
│   │   ├── loki/
│   │   ├── tempo/
│   │   └── grafana/
│   └── ingress/
│       └── nginx/
│
├── resources/                         # 第 2 层：逻辑资源（Kustomize overlay，同 services）
│   └── {domain}/
│       ├── kafka/
│       │   └── {topic-name}/
│       │       ├── base/
│       │       │   └── topic.yaml
│       │       └── overlays/
│       │           ├── dev/
│       │           ├── test/
│       │           ├── staging/
│       │           └── prod/
│       ├── mysql/
│       │   └── {instance-name}/
│       │       ├── base/
│       │       │   └── instance.yaml
│       │       └── overlays/
│       │           ├── dev/
│       │           ├── test/
│       │           ├── staging/
│       │           └── prod/
│       └── redis/
│           └── {instance-name}/
│               ├── base/
│               │   └── instance.yaml
│               └── overlays/
│                   ├── dev/
│                   ├── test/
│                   ├── staging/
│                   └── prod/
│
├── services/                          # 第 3 层：业务服务（Kustomize overlay）
│   └── {domain}/
│       └── {service-name}/
│           ├── base/
│           │   ├── deployment.yaml
│           │   ├── service.yaml
│           │   ├── ingress.yaml
│           │   └── kustomization.yaml
│           └── overlays/
│               ├── dev/
│               │   └── kustomization.yaml
│               ├── test/
│               │   └── kustomization.yaml
│               ├── staging/
│               │   └── kustomization.yaml
│               └── prod/
│                   └── kustomization.yaml
│
└── argocd/
    └── appset.yaml                    # ApplicationSet 定义（一个文件）
```

**路径公式（AI 直接套用）：**

| 资源类型 | 路径模板 |
|---------|---------|
| 服务 base | `services/{domain}/{service}/base/` |
| 服务环境 overlay | `services/{domain}/{service}/overlays/{env}/` |
| Kafka topic base | `resources/{domain}/kafka/{topic-name}/base/` |
| Kafka topic overlay | `resources/{domain}/kafka/{topic-name}/overlays/{env}/` |
| MySQL 实例 base | `resources/{domain}/mysql/{instance-name}/base/` |
| MySQL 实例 overlay | `resources/{domain}/mysql/{instance-name}/overlays/{env}/` |
| Redis 实例 base | `resources/{domain}/redis/{instance-name}/base/` |
| Redis 实例 overlay | `resources/{domain}/redis/{instance-name}/overlays/{env}/` |
| 平台基础设施 | `infrastructure/{category}/{component}/` |

**为什么按域而非按资源类型：**
- AI 创建服务时，同一个域的 service 和 resource 在相邻目录，路径规律一致
- ArgoCD ApplicationSet 可以按 `{domain}` 批量发现
- CODEOWNERS 可以按域设置审批权限
- 替代方案（按资源类型组织，如 `resources/kafka/order-events.yaml`）在跨域资源管理时路径不直观

---

### D2: .devops.yaml 定位 — 持续的声明式意图源

**问题：** .devops.yaml 是"一次性输入源"还是"持续的声明式意图源"？

**决策：持续的声明式意图源，但不是部署真相源。**

```yaml
# .devops.yaml — 放在代码仓库根目录
# 定位：服务的 DevOps 身份证 + 依赖声明（意图）
# 不包含：部署细节（副本数、资源限制、环境变量值）

service:
  name: order-service
  domain: trade
  team: trade-team
  owner: zhangsan

gitops:
  repo: https://gitlab.company.com/infra/gitops-repo
  path: services/trade/order-service

runtime:
  language: go
  port: 8080
  health_check: /healthz
  metrics: /metrics

dependencies:
  - name: order-db
    type: mysql
    role: owner          # owner = 我创建并拥有这个资源
  - name: order-events
    type: kafka-topic
    role: producer       # producer = 我拥有这个 topic
  - name: user-events
    type: kafka-topic
    role: consumer       # consumer = 我只是消费，别人拥有
```

**职责分离：**

| 信息类型 | 真相源 | 位置 |
|---------|-------|------|
| 服务身份（name/team/domain） | .devops.yaml | 代码仓库 |
| 配置仓库位置（repo/path） | .devops.yaml | 代码仓库 |
| 运行时配置（language/port） | .devops.yaml | 代码仓库 |
| 依赖声明（我需要什么） | .devops.yaml | 代码仓库 |
| 部署配置（replicas/资源/镜像tag） | Kustomize overlay | 配置仓库 |
| 资源定义（Kafka topic/MySQL 实例） | resources/{domain}/ | 配置仓库 |
| 中间件连接信息 | Operator 生成 | K8s 集群内 |

**工作流：**
1. 开发者修改 .devops.yaml（如新增依赖）
2. 开发者调用 `/devops`，AI 读取 .devops.yaml
3. AI 对比配置仓库现状，生成差异变更
4. AI 创建 MR 到配置仓库，开发者 review 后合并

**为什么不是一次性输入：** 如果 .devops.yaml 只在服务创建时使用，后续依赖变更时 AI 就没有代码仓库侧的意图源，只能靠对话记忆——这违反"单一真相源"原则，且 AI 更容易出错。

**为什么不把部署配置也放进来：** 部署配置（replicas、资源限制）是环境相关的，放在代码仓库会导致代码仓库需要感知环境差异，违反职责分离。

**漂移风险与缓解：** 开发者可能改了 .devops.yaml 但没运行 `/devops` 同步。缓解：代码仓库 CI 中检测 .devops.yaml 变更时提示开发者运行 `/devops`（提醒不阻塞）。AI 每次读取时也主动对比配置仓库现状并提示差异。

---

### D3: platform-inventory.yaml — 平台知识源与维护机制

```yaml
# platform-inventory.yaml — 放在配置仓库根目录
# 定位：AI 的"平台能力地图"，平台团队维护

clusters:
  - name: non-prod
    api_server: https://k8s-nonprod.company.com
    environments: [dev, test, staging]
  - name: prod
    api_server: https://k8s-prod.company.com
    environments: [prod]

environments:
  dev:    { cluster: non-prod, auto_deploy: true,  approval: none }
  test:   { cluster: non-prod, auto_deploy: false, approval: team }
  staging:{ cluster: non-prod, auto_deploy: false, approval: tech-lead }
  prod:   { cluster: prod,     auto_deploy: false, approval: tech-lead+sre }

domains:
  - name: trade
    team: trade-team
    namespaces:
      dev: dev-trade
      test: test-trade
      staging: staging-trade
      prod: prod-trade
  - name: user
    team: user-team
    namespaces:
      dev: dev-user
      test: test-user
      staging: staging-user
      prod: prod-user

naming:
  service: "{name}"
  namespace: "{env}-{domain}"
  mysql_instance: "{service}-db"
  redis_instance: "{service}-cache"
  kafka_topic: "{domain}.{service}.{event}"
  docker_image: "{registry}/{domain}/{service}:{git-sha-short}"
  label_app: "{service}"
  label_domain: "{domain}"

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

observability:
  metrics: { available: true, stack: prometheus }
  logging: { available: true, stack: loki }
  tracing: { available: true, stack: tempo }
  grafana: { url: "https://grafana.company.com" }

registry:
  url: harbor.company.com
  project: "{domain}"

gitlab:
  url: https://gitlab.company.com
  gitops_repo: infra/gitops-repo
```

**维护机制：**
- **写入权**：仅平台团队，通过 MR 修改，CODEOWNERS 保护
- **读取方**：AI Skill（读取平台能力）、ArgoCD ApplicationSet（读取集群/环境信息）
- **一致性保障**：配置仓库 CI 中可增加验证 job（检查 Operator CRD 是否存在于集群），不一致时告警但不阻塞。初期靠人工维护即可
- **变更触发场景**：新增中间件类型、新增业务域、命名规范调整、集群变更

**为什么不自动从集群同步：** 自动同步引入"谁是权威"的歧义——如果集群状态和 YAML 冲突，以谁为准？手动维护保持 YAML 为唯一权威，CI 验证只辅助检测漂移。

---

### D4: 环境管理 — 两集群四环境 + Kustomize overlay

**集群拓扑：**

| 集群 | 环境 | 用途 |
|------|------|------|
| non-prod | dev, test, staging | 开发、测试、预发布 |
| prod | prod | 生产 |

**环境隔离：namespace**
- 命名规则：`{env}-{domain}`（如 `dev-trade`、`prod-trade`）
- 同一集群内不同环境通过 namespace 隔离
- 跨域默认 NetworkPolicy deny-all，显式声明才允许

**Kustomize base 与 overlay 的内容边界：**

base/ 放"结构"（环境无关的完整定义），overlays/{env}/ 只放"差异值"。

```yaml
# services/trade/order-service/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  labels:
    app: order-service
    domain: trade
    team: trade-team
    managed-by: devops-skill
spec:
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
        domain: trade
    spec:
      containers:
        - name: order-service
          image: harbor.company.com/trade/order-service
          ports:
            - containerPort: 8080
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
          env:
            - name: SERVICE_NAME
              value: order-service
```

```yaml
# services/trade/order-service/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: dev-trade
images:
  - name: harbor.company.com/trade/order-service
    newTag: "latest"    # CI 直推时只更新此字段
patches:
  - target:
      kind: Deployment
      name: order-service
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
      - op: add
        path: /spec/template/spec/containers/0/resources
        value:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { cpu: 500m, memory: 512Mi }
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: ORDER_DB_HOST
          value: order-db.dev-trade.svc.cluster.local
```

**边界规则（AI 生成配置时遵循）：**

| 类别 | 放在 base | 放在 overlay |
|------|----------|-------------|
| Deployment 结构 | container/ports/probes | |
| 副本数 | | replicas |
| 资源限制 | | resources.requests/limits |
| 镜像 tag | | images.newTag |
| 环境变量-固定 | SERVICE_NAME 等 | |
| 环境变量-环境相关 | | DB_HOST/KAFKA_BOOTSTRAP 等 |
| Service | 完整定义 | |
| Ingress host | | host 域名 |
| ServiceMonitor | 完整定义 | |

**为什么选 overlay 而非每环境完整文件：** overlay 漏改时 `kustomize build` 报错（大声失败），完整文件漏改时静默使用旧值。符合底层原则"AI 操作不易出错"：遗漏比语法错误更危险。

**环境推进策略：**

| 环境 | 触发方式 | 审批 |
|------|---------|------|
| dev | CI 自动推送到配置仓库 main 分支 | 无需审批 |
| test | 创建 MR | 团队内 review |
| staging | 创建 MR | Tech Lead 审批 |
| prod | 创建 MR | Tech Lead + SRE 审批 |

---

### D5: GitOps 工作流联动 — CI 推送配置仓库

```
开发者 push 代码
    |
    v
[GitLab CI]
    |
    ├── 1. 代码检查 + 测试
    ├── 2. 构建镜像 → 推送 Harbor（tag = git sha 短哈希）
    └── 3. 更新配置仓库镜像 tag
            |
            ├── dev 环境：直接 push 到 main 分支（仅更新 image tag）
            └── 其他环境：创建 MR（包含 overlay patch 变更）
                    |
                    v
              [MR 审批] → merge → ArgoCD 自动同步 → K8s 部署
```

**"CI 直推"的精确含义：**

CI pipeline（GitLab Runner）直接 commit + push 到配置仓库 main 分支。具体操作：
1. Clone 配置仓库
2. 修改 `services/{domain}/{service}/overlays/dev/kustomization.yaml` 中的 `images[].newTag` 字段
3. `git commit -m "ci: update {service} image to {tag}"` + `git push`
4. ArgoCD 检测到 main 分支变更 → 自动同步 dev 环境

**安全边界：**

| 操作类型 | dev 环境 | test/staging/prod |
|---------|---------|------------------|
| 更新镜像 tag | CI 直推 main | CI 创建 MR |
| 修改部署配置（replicas 等） | AI 创建 MR | AI 创建 MR |
| 修改资源定义 | AI 创建 MR | AI 创建 MR |

关键区分：**只有 dev 环境的镜像 tag 更新是直推**，所有其他变更（包括 dev 的配置变更）都走 MR。

**凭证管理：**

| 凭证 | 用途 | 存储位置 | 生命周期 |
|------|------|---------|---------|
| GitLab Deploy Token | CI 推送配置仓库 | GitLab CI 变量（protected） | 有 expiry，定期轮换 |
| Harbor Robot Account | CI 推送镜像 | GitLab CI 变量（protected） | 按 project 隔离 |
| ArgoCD Repo Credential | ArgoCD 拉取配置仓库 | ArgoCD Secret（K8s） | 平台团队管理 |

选择 Deploy Token 而非 SSH Key：Token 可以在 GitLab UI 中随时撤销且有 expiry，更易管理。

---

### D6: ArgoCD ApplicationSet — 目录驱动自动发现

**两组 ApplicationSet，分别管理 services 和 resources：**

```yaml
# argocd/appset.yaml — services 部分
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: services
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://gitlab.company.com/infra/gitops-repo.git
              revision: HEAD
              directories:
                - path: "services/*/*/overlays/*"
          - clusters:
              selector:
                matchLabels:
                  env: "{{ index .path.segments 4 }}"
  template:
    metadata:
      name: "{{ index .path.segments 2 }}-{{ index .path.segments 4 }}"
      # 例：order-service-dev
    spec:
      project: default
      source:
        repoURL: https://gitlab.company.com/infra/gitops-repo.git
        targetRevision: HEAD
        path: "{{ .path.path }}"
      destination:
        server: "{{ .server }}"
        namespace: "{{ index .path.segments 4 }}-{{ index .path.segments 1 }}"
        # 例：dev-trade
```

**集群标签约定：** ArgoCD 中注册集群时打标签 `env: dev/test/staging/prod`。非生产集群注册多次（分别对应 dev/test/staging 三个环境），通过标签区分。

**为什么用 Matrix generator：** 服务需要交叉匹配"目录结构"和"环境到集群映射"两个维度。Matrix generator 是 ApplicationSet 的标准方式，避免硬编码集群地址。

**注意：** path segment 索引取决于 directories.path 的层级。实际索引需要在实现时按 ArgoCD 文档校验，此处展示设计意图。

**AI 操作可靠性保障：** AI 只需按路径公式（D1）创建正确的目录结构，ApplicationSet 自动发现。**AI 永远不需要碰 argocd/ 目录**——这是关键。

**按环境区分的同步策略：**

| 环境 | Auto-Sync | Self-Heal | Prune | 理由 |
|------|-----------|-----------|-------|------|
| dev | 开启 | 开启 | 开启 | 快速迭代，CI 直推后立即部署 |
| test | 关闭 | 开启 | 关闭 | MR 合并后手动触发 sync |
| staging | 关闭 | 开启 | 关闭 | 模拟生产，需确认后同步 |
| prod | 关闭 | 开启 | 关闭 | 最严格，需审批后手动 sync |

- **Auto-Sync**：Git 变更后是否自动部署。仅 dev 开启
- **Self-Heal**：有人手动 kubectl 改了集群，是否自动恢复到 Git 定义的状态。全环境开启，确保 GitOps 一致性
- **Prune**：Git 中删除的资源是否自动从集群删除。仅 dev 开启，其他环境手动处理避免误删
- **Health Check**：使用 ArgoCD 内置 Deployment rollout 状态检查，无需自定义

---

### D7: resources 目录的环境策略

**问题：** 中间件资源（Kafka topic、MySQL 实例）在不同环境怎么管理？

**决策：resources 也使用 Kustomize overlay，和 services 保持一致。**

```yaml
# resources/trade/mysql/order-db/base/instance.yaml
apiVersion: mysql.oracle.com/v2
kind: InnoDBCluster
metadata:
  name: order-db
  labels:
    app: order-db
    domain: trade
    owner: order-service
    managed-by: devops-skill
spec:
  instances: 1
  router:
    instances: 1
  tlsUseSelfSigned: true

# resources/trade/mysql/order-db/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: dev-trade
# dev 用 base 默认值即可，无需额外 patch

# resources/trade/mysql/order-db/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: prod-trade
patches:
  - target:
      kind: InnoDBCluster
      name: order-db
    patch: |
      - op: replace
        path: /spec/instances
        value: 3
      - op: replace
        path: /spec/router/instances
        value: 2
```

**环境差异示例：**

| 资源 | base（dev 默认值） | prod overlay patch |
|------|-------------------|-------------------|
| MySQL | 1 副本，默认存储 | 3 副本，大存储 |
| Redis | 64Mi 内存 | 2Gi 内存 |
| Kafka topic | 1 分区 | 6 分区 |

**为什么 resources 也用 overlay（和 services 一致）：**
1. **AI 只需掌握一个模式**——services 和 resources 都是 base + overlays/{env}/，降低出错概率
2. **环境差异从第一天就存在**——prod 的 MySQL 不可能和 dev 一样配 1 副本
3. **ApplicationSet 匹配规则可复用**——都是扫 `*/overlays/{env}/` 目录

---

### D8: 命名规范 — AI 可机械式套用

| 资源 | 规则 | 示例 | 校验正则 |
|------|------|------|---------|
| 服务名 | 小写字母 + 数字 + 连字符，2-40 字符 | `order-service` | `^[a-z][a-z0-9-]{1,39}$` |
| namespace | `{env}-{domain}` | `dev-trade` | `^(dev\|test\|staging\|prod)-[a-z][a-z0-9-]+$` |
| MySQL 实例 | `{service}-db` | `order-service-db` | — |
| Redis 实例 | `{service}-cache` | `order-service-cache` | — |
| Kafka topic | `{domain}.{service}.{event}` | `trade.order-service.created` | — |
| Docker 镜像 | `{registry}/{domain}/{service}:{git-sha-short}` | `harbor.company.com/trade/order-service:a1b2c3d` | — |
| label: app | `{service}` | `order-service` | — |
| label: domain | `{domain}` | `trade` | — |
| label: env | `{env}` | `dev` | — |
| label: team | `{team}` | `trade-team` | — |
| label: managed-by | 固定值 | `devops-skill` | — |

**冲突检测：** AI 创建资源前，检查配置仓库目录/文件是否已存在同名路径。路径即唯一标识——同域下不允许同名资源。

---

### D9: 资源所有权模型

| 资源类型 | 所有者规则 | 共享方式 |
|---------|-----------|---------|
| MySQL 实例 | 创建者拥有（通常独占） | 一般不共享 |
| Redis 实例 | 创建者拥有（通常独占） | 一般不共享 |
| Kafka topic | producer 拥有 | consumer 通过 .devops.yaml 声明引用 |

**依赖追踪：** AI 通过扫描所有服务的 `.devops.yaml` 文件构建依赖图。删除资源前，AI 检查是否有其他服务声明了对该资源的依赖。

**跨域依赖：** 允许，但 AI 需要明确提示"这是一个跨域依赖"并要求确认。跨域依赖在 NetworkPolicy 中需要显式放通。

---

### D10: Day 0 — 平台初始化流程

```
阶段一：手动引导（平台团队执行一次）
  1. 创建两个 K8s 集群（non-prod + prod）
  2. 在 GitLab 创建配置仓库 gitops-repo
  3. 初始化目录结构 + 创建 platform-inventory.yaml
  4. 创建 infrastructure/ 目录，放入 Operator 和基础设施 Helm chart
  5. 手动 helm install 安装 ArgoCD（唯一一次手动操作）
  6. 配置 ArgoCD 连接配置仓库和两个集群

阶段二：ArgoCD 接管（自动）
  7. ArgoCD 同步 infrastructure/ → 安装 Operators、监控栈、Ingress
  8. 创建 argocd/appset.yaml → ApplicationSet 开始监听目录结构
  9. 平台就绪

阶段三：首个服务验证
  10. 部署一个 demo 服务，验证完整链路
      （代码推送 → CI → 镜像 → 配置更新 → ArgoCD 同步 → 部署）
  11. 验证 Skill 能正确读取 platform-inventory.yaml
```

**ArgoCD 自身不做 GitOps 管理：** 避免"自己管理自己"的循环依赖。ArgoCD 的升级和配置变更由平台团队通过 Helm 手动管理。这是业界标准做法。

---

## Risks / Trade-offs

**R1: 单一配置仓库可能成为瓶颈**
→ 初期不拆分，监控 MR 合并冲突频率。当同时打开的 MR 经常冲突时，按域拆分为独立仓库。ApplicationSet 天然支持多仓库，目录结构不变，迁移成本可控。中小规模（<100 服务）至少 2-3 年不会成为瓶颈。

**R2: platform-inventory.yaml 与集群实际状态漂移**
→ 初期靠人工维护。出现不一致时，AI 生成的资源会在 ArgoCD 同步阶段失败（大声失败，可接受）。后续可增加自动校验 CronJob。

**R3: Kustomize overlay 学习成本**
→ AI 生成所有 overlay，业务团队不需要直接编写。Review MR 时需理解 patch 语法。缓解：AI 在 MR 描述中展示"最终渲染结果"（`kustomize build` 输出）降低 review 难度。

**R4: ApplicationSet path 匹配错误导致服务不被发现**
→ 目录结构不符合规范时服务静默不被发现。缓解：AI 创建完成后主动检查 ArgoCD Application 是否出现，超时则告警。配置仓库 CI 增加目录结构规范校验。

**R5: CI 直推 dev 的安全隐患**
→ Deploy Token 泄露可能污染配置仓库。缓解：Token 有 expiry 定期轮换；直推范围限制为 `overlays/dev/` 下的 `newTag` 字段；main 分支 protection 只允许 CI bot 和平台团队推送。

**R6: .devops.yaml 与配置仓库漂移**
→ 开发者改了 .devops.yaml 但没同步。缓解：代码仓库 CI 检测变更时提示（不阻塞）；AI 每次读取时主动对比并提示差异。

**R7: JSON Patch 语法复杂性**
→ AI 可能写错 patch path。缓解：Skill 的 platform-spec.md 提供标准 patch 模板，常见操作用固定模板而非动态生成；`kustomize build` 在 CI 中验证，语法错误立即发现。

**Trade-off: 灵活性 vs 一致性**
本设计偏向一致性——强命名规范、固定目录结构、统一 overlay 模式。牺牲了一些灵活性（如某服务想用非标结构），换来 AI 操作的可靠性。特殊需求可在 Skill 中添加例外处理，但默认路径必须标准化。

---

## Open Questions

**Q1: 配置仓库自身的 CI pipeline 内容**
→ 需要在 Change 3 中定义。初步方向：YAML lint + `kustomize build` 验证 + 命名规范检查 + 目录结构规范校验。

**Q2: 域的增删改流程**
→ 新增域需要更新 platform-inventory.yaml + 创建 namespace + 创建 CODEOWNERS 条目。低频操作，初期平台团队手动完成，后续可纳入 skill flow。
