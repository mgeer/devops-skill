# DevOps 平台规划

## 一、愿景

基于 GitLab + GitLab Runner + ArgoCD + GitOps 构建公司内部 DevOps 平台，以 AI Skill 作为交互界面，让开发者通过自然语言指挥 AI 完成所有 DevOps 操作。

**核心理念：平台即契约（Platform as Contract）**

- 规范不是文档，而是内嵌在 AI 行为中的知识
- 开发者不需要记住规范，只需要会指挥 AI
- 规范更新 = 更新 skill 文件，所有人立刻获得最新规范

**底层设计原则：AI 操作不易出错**

所有架构和文件结构的设计决策，以"AI 操作不易出错"为第一判断标准。人看到的信息由 AI 实时整理，不受底层文件结构约束。

- 底层文件结构为 AI 操作优化，不为人类阅读优化
- 人需要的任何视图（差异对比、全貌总览、依赖图）由 AI 按需生成
- 优先选择"出错时大声失败"的方案，避免"静默失败到线上才发现"
- 优先选择单一真相源，避免需要同步多份数据

**目标：**

- 服务开发高效 — 新服务接入平台只需一次对话
- 运行稳定 — GitOps 声明式管理，变更可追溯可回滚
- 维护简单 — AI 辅助排查、监控、告警，减少对运维的依赖
- 依赖管理容易 — 中间件声明式创建，依赖关系清晰可查

---

## 二、整体架构概览

```
开发者 push/MR
    |
    v
[GitLab 代码仓库] --触发CI--> [GitLab Runner]
                                    |
                              代码检查/测试/构建
                                    |
                        +-----------+-----------+
                        |                       |
                        v                       v
                  [Harbor 镜像仓库]      [GitOps 配置库]
                    (存储镜像)           (更新镜像 tag)
                        |                       |
                        |                 ArgoCD 自动监听
                        |                       |
                        |                       v
                        +-------------> [Kubernetes 集群]
                          (拉取镜像部署)
```

### 两个仓库职责分离

| 仓库 | 内容 | 谁改 | 改动频率 |
|------|------|------|----------|
| 代码仓库（每服务一个） | 业务代码、Dockerfile、.gitlab-ci.yml、.devops.yaml | 开发者 | 高 |
| 配置仓库（全公司一个） | 部署配置、中间件声明、环境差异、ArgoCD 定义 | CI 自动 + 开发者/AI | 中 |

### 配置仓库三层结构

```
gitops-repo/
│
├── platform-inventory.yaml      ← Skill 的"能力地图"
│
├── infrastructure/              ← 第 1 层：平台基础设施
│   ├── operators/               │  平台团队管理
│   │   ├── strimzi-kafka.yaml   │  改动频率：很低
│   │   ├── mysql-operator.yaml  │  审批：SRE/平台团队
│   │   └── redis-operator.yaml  │
│   ├── kafka/                   │
│   │   └── cluster.yaml         │
│   ├── monitoring/              │
│   │   ├── prometheus.yaml      │
│   │   ├── loki.yaml            │
│   │   ├── tempo.yaml           │
│   │   └── grafana.yaml         │
│   └── ingress/                 │
│       └── nginx.yaml           │
│
├── resources/                   ← 第 2 层：逻辑资源
│   ├── kafka/                   │  业务团队通过 /devops 管理
│   │   └── order-events.yaml    │  改动频率：偶尔
│   ├── mysql/                   │  审批：Tech Lead
│   │   └── order-db.yaml        │
│   └── redis/                   │
│       └── order-cache.yaml     │
│
├── services/                    ← 第 3 层：业务服务
│   └── order-service/           │  业务团队通过 /devops 管理
│       ├── base/                │  改动频率：频繁
│       │   ├── deployment.yaml  │  审批：团队内部
│       │   ├── service.yaml     │
│       │   ├── ingress.yaml     │
│       │   └── service-monitor.yaml
│       ├── dependencies.yaml    │
│       └── overlays/            │
│           ├── dev/             │
│           ├── staging/         │
│           └── prod/            │
│
└── argocd/                      ← ArgoCD Application 定义
    ├── infrastructure.yaml
    ├── resources.yaml
    └── services/
        └── order-service.yaml
```

### 资源管理规则

**所有权模型：**

- 每个 resource 有且只有一个 owner
- Kafka Topic: owner = producer（谁产生数据谁拥有）
- MySQL / Redis: owner = 创建服务（通常独占）
- 修改或删除共享资源前，必须检查所有引用者

**资源定义与依赖引用分离：**

```
resources/kafka/order-events.yaml     → 资源真正被创建（唯一真相源）
services/xxx/dependencies.yaml        → 仅声明"我用了什么"（引用）
```

**中间件创建模式：**

| 中间件 | 集群层 | 资源层 | 创建方式 |
|--------|--------|--------|----------|
| Kafka | 共享集群（平台部署） | 按需创建 Topic | Skill 创建 resources/kafka/xxx.yaml |
| MySQL | 共享 Operator（平台部署） | 按需创建独立实例 | Skill 创建 resources/mysql/xxx.yaml |
| Redis | 共享 Operator（平台部署） | 按需创建独立实例 | Skill 创建 resources/redis/xxx.yaml |

**基础设施缺失时的处理：**

Skill 通过 `platform-inventory.yaml` 判断平台能力。当某中间件 `available: false` 时，Skill 引导开发者联系平台团队，或帮助生成 `infrastructure/` 下的配置文件交由平台团队审批。

---

## 三、交互界面：/devops Skill

Skill 是开发者与平台交互的唯一入口。

### 交互设计

**入口：只有一个命令**

```
/devops                  ← 无参数，自动检测当前服务状态并引导
/devops <自然语言>        ← 用意图驱动，不用记命令和参数
```

**示例：**

```
/devops 我要新建一个用户服务
/devops 需要用 MySQL 存储订单数据
/devops 部署到测试环境
/devops 线上报错了帮我看看
/devops 接口慢了想加个告警
/devops 这个服务不要了
```

**核心原则（按优先级排序）：安全 > 准确 > 可追溯 > 体验**

**P0 安全 — 不做危险操作，变更只走 Git 流程**

1. **AI 只生成配置，不直接执行危险操作** — AI 的产出是 YAML 文件和 MR，不是直接操作集群
2. **禁止的操作** — AI 不得执行以下操作，只能生成配置交由流程审批：
   - 直接 kubectl apply/delete 操作生产集群
   - 直接修改生产环境数据库
   - 删除正在被其他服务引用的资源
   - 修改 infrastructure/ 下的平台基础设施配置
3. **AI 可以做的** — 生成/修改配置文件、提交到 Git、创建 MR、查询状态和日志
4. **变更通过 Git 流程生效** — 所有变更都是"改 YAML → 提 MR → 审批 → ArgoCD 同步"，没有捷径

**P1 准确 — 不猜测，多确认**

5. **不猜意图** — 理解不了就问，不要假设用户想做什么
6. **不猜参数** — 服务名、资源名、环境等关键信息，必须用户明确给出或确认
7. **操作前必确认** — 展示完整的操作方案和将要修改的文件，等用户确认后才执行
8. **信息可推断时也要确认** — 比如从目录名推断服务名，要说"检测到服务名是 order-service，对吗？"
9. **分步确认而非批量** — 涉及多个操作时逐步确认，不要一次性列一大堆让用户判断
10. **宁可多问一句，不可做错一步** — 做错了要回滚，成本远大于多问一个问题

**P2 可追溯 — 每一步操作都有记录，出了问题能查到谁、什么时候、改了什么**

11. **MR 描述规范** — 记录操作发起人、AI 理解到的意图、影响的服务和资源
12. **commit message 规范** — 包含操作来源（/devops skill）和操作意图
13. **不允许绕过 Git** — 所有变更必须留痕，没有"口头操作"

**P3 体验 — 自然语言交互，流畅引导**

14. **自然语言驱动** — 用户说意图，不用记命令和参数
15. **智能引导** — 检测当前状态，主动提示下一步该做什么
16. **在不违反 P0-P2 的前提下**，尽量减少用户需要输入的信息量

**AI 的处理逻辑：**

```
用户输入（自然语言或无参数）
    |
    v
理解意图，识别场景
    |
    +--> 意图不清晰？ --> 追问，不要猜
    |
    v
读取 .devops.yaml（了解当前服务）
读取 platform-inventory.yaml（了解平台能力）
    |
    v
检查前置条件是否满足
    |
    +--> 不满足？ --> 告知缺什么，引导解决
    |
    v
收集必要信息（逐个确认，不猜测）
    |
    v
生成操作方案，展示将要做的变更
    |
    +--> 用户说不对？ --> 调整方案
    |
    v
用户确认 --> 执行 --> 展示结果
```

### Skill 的核心文件

```
~/.claude/skills/devops/
├── skill.md                  # 主入口 prompt（行为逻辑 + 核心原则）
├── platform-spec.md          # 平台架构规范（Phase 1 交付物）
├── flows/                    # 场景交互设计（Phase 2 交付物）
│   ├── create-service.md     # 新建服务（含依赖）
│   ├── add-dependency.md     # 添加/引用中间件依赖
│   ├── deploy.md             # 部署与环境推进
│   ├── db-migration.md       # 数据库变更管理
│   ├── observe-alert.md      # 可观测性与告警配置
│   ├── troubleshoot.md       # 线上排查与回滚
│   ├── decommission.md       # 服务下线与资源清理
│   └── local-dev.md          # 本地开发环境配置
└── examples/                 # 参考配置示例
```

### 关键配置文件

**.devops.yaml（每个服务根目录）— 服务的 DevOps 身份证：**

```yaml
# .devops.yaml 只记录服务自身的基本信息
# 依赖关系和部署配置在配置仓库中管理（待决策项 #14 确定最终方案）
service:
  name: order-service
  team: trade-team
  owner: zhangsan

gitlab:
  url: https://gitlab.company.com/backend/order-service

gitops:
  repo: https://gitlab.company.com/infra/gitops-repo
  path: services/order-service

runtime:
  language: go
  port: 8080
  health_check: /healthz
  metrics: /metrics
```

**platform-inventory.yaml（配置仓库根目录）— 平台能力清单：**

```yaml
platform:
  cluster: production-cluster
  kubernetes: "1.29"

middleware:
  kafka:
    available: true
    operator: strimzi
    clusters:
      - name: kafka-cluster
        namespace: kafka
        bootstrap: kafka-cluster-kafka-bootstrap.kafka.svc:9092
  mysql:
    available: true
    operator: oracle-mysql-operator
  redis:
    available: true
    operator: redis-operator
  elasticsearch:
    available: false
    note: "计划 Q2 上线"

observability:
  metrics: { available: true, stack: prometheus }
  logging: { available: true, stack: loki }
  tracing: { available: true, stack: tempo }
  grafana: { url: "https://grafana.company.com" }

registry:
  url: harbor.company.com

gitlab:
  url: https://gitlab.company.com
  gitops_repo: infra/gitops-repo
```

---

## 四、实施计划

### Phase 1：平台架构规范

**目标：** 把平台的"游戏规则"定下来，形成 AI 和人都能理解的规范文档。

**性质：** 规则、约束、结构。定义后相对稳定。

**内容：**

| 模块 | 要定义的内容 | 状态 |
|------|-------------|------|
| 1.1 整体架构 | 三层分离、配置仓库结构、职责边界 | 已讨论，待正式化 |
| 1.2 多集群设计 | dev/staging 集群 vs prod 集群、ArgoCD 多集群管理、镜像跨集群访问 | 待设计 |
| 1.3 资源管理 | 中间件类型、所有权规则、依赖引用机制、生命周期 | 已讨论，待正式化 |
| 1.4 CI/CD 流程 | 流水线阶段、镜像 tag 策略、环境推进策略、数据库变更管理 | 待设计 |
| 1.5 回滚策略 | 纯代码回滚、涉及 DB 变更的回滚、多服务联动回滚 | 待设计 |
| 1.6 可观测性 | 分层标准、自动 vs 手动、日志格式、告警分级 | 待设计 |
| 1.7 配置文件 Schema | .devops.yaml、platform-inventory.yaml 字段定义、消除信息重复 | 已讨论，待正式化 |
| 1.8 命名规范 | 服务名、资源名、namespace、label 的命名规则 | 待设计 |
| 1.9 网络与安全 | Ingress 规则、服务间调用方式、NetworkPolicy、中间件访问控制 | 待设计 |
| 1.10 Secret 管理 | Operator 密码传递、业务 Secret 管理方式 | 待设计 |
| 1.11 环境差异化 | overlay 方案、环境变量管理 | 待设计 |
| 1.12 资源配额 | CPU/内存规格等级、namespace 配额、超额审批流程 | 待设计 |
| 1.13 备份恢复 | 数据库自动备份策略、保留周期、恢复方式（自助 vs 运维） | 待设计 |
| 1.14 灰度发布 | 金丝雀发布、蓝绿部署、自动回滚（Argo Rollouts） | 待设计 |
| 1.15 本地开发 | 本地运行方式、本地中间件依赖、与线上环境差异最小化 | 待设计 |

**交付物：** `platform-spec.md`（后续直接作为 Skill 的知识文件）

### Phase 2：使用场景设计

**目标：** 让开发者使用 /devops 时体验流畅、不困惑。

**性质：** 产品设计，关注用户体验，需要反复打磨。

**需要设计的场景：**

| 场景 | 关注的体验问题 | 对应 flow 文件 |
|------|---------------|---------------|
| 新建服务（含依赖） | 要问几个问题？什么顺序？哪些可以自动推断？ | create-service.md |
| 添加/引用中间件依赖 | 新建 vs 引用已有？怎么展示列表？怎么选择？ | add-dependency.md |
| 部署与环境推进 | 环境推进怎么触发？状态怎么展示？ | deploy.md |
| 数据库变更 | migration 文件怎么管理？和部署顺序怎么联动？ | db-migration.md |
| 可观测性与告警 | 自然语言转 PromQL 的准确性？确认方式？ | observe-alert.md |
| 线上排查 + 回滚 | 信息怎么聚合展示？回滚确认的粒度？涉及 DB 变更时怎么办？ | troubleshoot.md |
| 服务下线 | 依赖检查、资源清理的引导流程？ | decommission.md |
| 本地开发环境 | 本地怎么跑？怎么连依赖？和线上差异怎么最小化？ | local-dev.md |

**每个场景需要定义：**

- 触发方式（命令 / 自动检测）
- 信息采集（哪些问用户、哪些自动推断）
- 操作确认（粒度、展示格式）
- 异常处理（出错提示、恢复建议）
- 完成反馈（做了什么、下一步建议）

**交付物：** `flows/*.md`（每个场景一个交互设计文档）

### Phase 3：Skill 开发

**目标：** 将 Phase 1 的规范 + Phase 2 的场景设计转化为可执行的 AI Skill。

**依赖：** Phase 1 和 Phase 2 基本完成。

**开发顺序（建议）：**

1. `skill.md` — 主入口 prompt（意图识别 + 核心原则 + 场景分发）
2. `platform-spec.md` — 直接使用 Phase 1 文档
3. `flows/create-service.md` — 最核心的场景，先跑通
4. `flows/add-dependency.md` — 第二核心
5. `flows/deploy.md` — 第三核心
6. 其余 flows 逐步补充
7. `examples/` — 从实际使用中积累

**迭代方式：** 先做最小可用版本，用真实项目试用，根据反馈迭代。

---

## 五、待讨论决策清单

以下问题在 Phase 1 推进过程中需要逐一讨论确定：

**技术决策：**

| # | 决策项 | 选项 | 当前倾向 |
|---|--------|------|----------|
| 1 | 配置管理方式 | Kustomize vs Helm | Kustomize（AI 操作原生 YAML 更可靠） |
| 2 | Secret 管理 | Sealed Secrets / External Secrets + Vault / K8s 原生 | 待定 |
| 3 | 环境差异化 | 每环境独立文件 / overlay patch / 环境变量 | 待定 |
| 4 | Skill 操作配置仓库方式 | Clone 到本地 / GitLab API / 约定目录 | 倾向 GitLab API（更安全） |
| 5 | Skill 分发方式 | 全局安装 / Git 仓库 + symlink | 待定 |
| 6 | 服务间调用 | 直接 DNS / Service Mesh (Istio) | 待定 |
| 7 | 日志格式 | 结构化 JSON / 纯文本 | 待定 |
| 8 | 技术栈支持范围 | Go / Java / Node / Python / 其他 | 待定 |
| 9 | 数据库变更工具 | flyway / golang-migrate / liquibase | 待定 |
| 10 | 灰度发布方案 | Argo Rollouts / Istio 流量管理 / 原生滚动更新 | 待定 |
| 11 | 本地开发方案 | docker-compose / telepresence / 其他 | 待定 |

**架构决策：**

| # | 决策项 | 选项 | 当前倾向 |
|---|--------|------|----------|
| 12 | 集群拓扑 | 单集群多 namespace / 双集群（dev+prod）/ 多集群 | 待定 |
| 13 | 配置仓库拆分 | 全公司一个 / 按业务域拆分 / 每团队一个 | 暂定全公司一个，CODEOWNERS 控权限 |
| 14 | .devops.yaml vs dependencies.yaml | 合并 / 分离（意图 vs 连接配置）/ 去掉一个 | 待定 |
| 15 | 数据库备份 | Operator 内置备份 / Velero / 自定义 CronJob | 待定 |
| 16 | 资源规格等级 | 自由填写 / 预定义等级（S/M/L）/ 预定义+超额审批 | 待定 |
