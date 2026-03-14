## ADDED Requirements

### Requirement: Skill 入口设计

/devops skill SHALL 提供两种调用方式：

1. `/devops` — 无参数，AI 自动检测当前上下文（代码仓库、.devops.yaml）并引导
2. `/devops <自然语言>` — 用户用自然语言描述意图

#### Scenario: 无参数调用

- **WHEN** 开发者在代码仓库中运行 `/devops`
- **THEN** AI SHALL 读取 .devops.yaml，检查服务当前状态（是否已接入、配置是否同步），主动引导下一步操作

#### Scenario: 自然语言调用

- **WHEN** 开发者运行 `/devops 我要新建一个用户服务`
- **THEN** AI SHALL 解析意图为"创建服务"，进入创建服务流程

#### Scenario: 意图不清晰

- **WHEN** 开发者运行 `/devops 帮我搞一下`
- **THEN** AI SHALL 追问"请描述您想做什么？例如：创建服务、添加依赖、部署到某环境"，不得猜测意图

---

### Requirement: 核心原则 — 安全（P0）

AI SHALL 遵守以下安全规则，任何情况下不得违反：

1. AI 的产出是 YAML 文件和 MR，不得直接操作集群
2. 禁止 AI 执行：kubectl apply/delete 生产集群、修改生产数据库、删除被引用的资源、修改 infrastructure/ 目录（需走 MR）
3. AI 可以做：生成/修改配置文件、提交 Git、创建 MR、查询状态和日志
4. 所有变更通过 Git 流程生效："改 YAML → 提 MR → 审批 → ArgoCD 同步"

#### Scenario: 用户要求直接操作集群

- **WHEN** 开发者说"帮我直接把 prod 的副本数改成 5"
- **THEN** AI SHALL 拒绝直接操作，改为"我会创建一个 MR 将 prod 副本数改为 5，审批后由 ArgoCD 自动同步"

#### Scenario: 用户要求删除被引用的资源

- **WHEN** 开发者要求删除一个有 consumer 的 Kafka topic
- **THEN** AI SHALL 拒绝并列出所有消费者，要求先移除依赖

#### Scenario: 修改 infrastructure 目录

- **WHEN** AI 需要修改 `infrastructure/` 下的文件
- **THEN** AI SHALL 通过 MR 提交，reviewer MUST 包含平台团队

---

### Requirement: 核心原则 — 准确（P1）

AI SHALL 遵守以下准确性规则：

1. 不猜意图——理解不了就问
2. 不猜参数——服务名、资源名、环境等关键信息 MUST 由用户明确给出或确认
3. 操作前必确认——展示完整方案和将要修改的文件，等确认后才执行
4. 可推断的信息也要确认——如"检测到服务名是 order-service，对吗？"
5. 分步确认——涉及多个操作时逐步确认，不批量

#### Scenario: 推断服务名需确认

- **WHEN** AI 从当前目录名推断服务名为 order-service
- **THEN** AI SHALL 提示"检测到当前服务为 order-service（来源：.devops.yaml），确认？"

#### Scenario: 操作前展示方案

- **WHEN** AI 准备创建一个服务的配置文件
- **THEN** AI SHALL 先展示将要创建的文件列表和关键配置内容，等用户确认后再执行

#### Scenario: 多步操作分步确认

- **WHEN** 创建服务需要同时创建 MySQL 和 Kafka topic
- **THEN** AI SHALL 先确认服务基本信息，再逐个确认每个依赖的配置，不一次性列出所有内容

---

### Requirement: 核心原则 — 可追溯（P2）

所有 AI 操作 SHALL 留下可追溯的记录：

1. MR 描述包含操作发起人、AI 理解的意图、影响的服务和资源
2. Commit message 包含操作来源（/devops skill）和操作意图
3. 不允许绕过 Git——没有"口头操作"

#### Scenario: AI 创建的 commit message

- **WHEN** AI 提交配置变更
- **THEN** commit message SHALL 包含 `[devops-skill]` 前缀和操作意图，如 `[devops-skill] create order-service base config`

#### Scenario: AI 创建的 MR 描述

- **WHEN** AI 创建 MR
- **THEN** MR 描述 SHALL 包含：操作发起人、意图、影响范围、变更摘要

---

### Requirement: 核心原则 — 体验（P3）

在不违反 P0-P2 的前提下，AI SHALL 提供流畅的交互体验：

1. 自然语言驱动——用户说意图，不用记命令和参数
2. 智能引导——检测当前状态，主动提示下一步
3. 减少输入——尽量自动推断信息（但推断结果要确认）

#### Scenario: 智能引导

- **WHEN** AI 检测到服务已创建但未部署到任何环境
- **THEN** AI SHALL 提示"order-service 已创建配置但尚未部署，是否部署到 dev 环境？"

#### Scenario: 体验不能违反安全

- **WHEN** 为了"方便"可以跳过确认直接执行
- **THEN** AI MUST 不跳过确认（P1 优先于 P3）

---

### Requirement: AI 处理逻辑框架

AI 收到用户输入后 SHALL 按以下顺序处理：

```
1. 解析意图（自然语言 → 操作类型）
2. 读取上下文（.devops.yaml + platform-inventory.yaml）
3. 检查前置条件（域是否存在、中间件是否可用、资源是否冲突）
4. 收集必要信息（逐个确认，不猜测）
5. 生成操作方案（展示将要做的变更）
6. 用户确认
7. 执行操作（生成 YAML / 创建 MR）
8. 展示结果（做了什么、下一步建议）
```

#### Scenario: 前置条件不满足

- **WHEN** 用户请求创建 MySQL 实例，但 platform-inventory.yaml 中 mysql.available=false
- **THEN** AI SHALL 在步骤 3 停止，提示"MySQL 尚未在平台上线，请联系平台团队"

#### Scenario: 收集信息阶段

- **WHEN** 用户请求"新建一个服务"但未提供服务名
- **THEN** AI SHALL 在步骤 4 询问"请提供服务名称"，不得自行生成

---

### Requirement: Skill 文件结构

/devops skill 的文件 SHALL 按以下结构组织：

```
devops-skill/
├── skill.md                  # 主入口（行为逻辑 + 核心原则）
├── platform-spec.md          # 平台架构规范（本 change 的产出）
├── flows/                    # 场景交互设计（后续 change 的产出）
│   ├── create-service.md
│   ├── add-dependency.md
│   ├── deploy.md
│   ├── db-migration.md
│   ├── observe-alert.md
│   ├── troubleshoot.md
│   ├── decommission.md
│   └── local-dev.md
└── examples/                 # 参考配置示例
```

本 change 只交付 skill.md 骨架和 platform-spec.md。flows/ 和 examples/ 由后续 change 逐步补充。

#### Scenario: skill.md 骨架内容

- **WHEN** 本 change 完成后
- **THEN** skill.md SHALL 包含：核心原则（P0-P3）、AI 处理逻辑框架、意图识别分类、platform-spec.md 引用。不包含具体 flow 实现

#### Scenario: platform-spec.md 内容

- **WHEN** 本 change 完成后
- **THEN** platform-spec.md SHALL 包含：配置仓库结构、命名规范、环境管理、GitOps 工作流、资源所有权模型——即本 change 所有 capability 的规范汇总，作为 AI 的知识文件
