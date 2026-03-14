## Context

Change 1 定义了配置仓库结构、命名规范、环境管理、GitOps 工作流、资源所有权模型等"地基"。本 change 在此地基之上，设计开发者日常与平台交互的核心操作流程：初始化服务、管理依赖、下线服务，以及支撑这些流程的 Secret 管理和资源规格方案。

**当前状态：** Change 1 的 skill.md 骨架已包含 P0-P3 原则和 AI 处理逻辑框架，但缺少具体的操作流程（flows/）。开发者无法真正使用平台。

**核心约束：**
- 底层原则不变：**AI 操作不易出错**
- AI 的操作边界不变：只生成 YAML 和创建 MR，不直接操作集群
- 本 change 依赖 Change 1 定义的所有规范（目录结构、命名规范、.devops.yaml schema、overlay 模式等）
- Skill 通过 MCP 操作 Git 仓库（clone/commit/push/MR），需要用户安装 MCP

**利益相关方：**
- 开发者：通过 `/devops` 初始化服务、添加依赖、下线服务
- 平台团队：维护 Secret Operator、定义资源规格标准、审批超额请求
- SRE：审批生产环境相关 MR

---

## Goals / Non-Goals

**Goals:**

- 设计 init-service 完整交互流程：从已有代码仓库出发，AI 分析代码推断信息、引导确认、生成 .devops.yaml 和配置仓库文件
- 设计 add-dependency 完整交互流程：为已接入服务添加/引用中间件依赖，同步到配置仓库
- 设计 decommission 完整交互流程：安全下线服务，含依赖检查和分步清理
- 确定 Secret 管理方案：AI 不接触密码值，利用 Operator 自动生成 + 命名约定
- 确定资源规格方案：预定义等级 + 超额审批机制
- 定义 CI 配置检查规范：AI 检查 .gitlab-ci.yml 合理性，缺失或有问题时引导
- 确定 Skill 操作配置仓库的方式和前置条件

**Non-Goals:**

- CI/CD 流水线阶段定义（Change 3）
- 环境推进与部署流程（Change 3）
- 可观测性配置（Change 4）
- NetworkPolicy 生成（Change 5）
- .gitlab-ci.yml 的标准阶段和模板设计（Change 3，本 change 只做检查）

---

## Decisions

### D1: Skill 操作配置仓库方式 — MCP clone 到本地

**问题：** Skill 需要操作配置仓库（读取 platform-inventory.yaml、创建服务目录、创建 MR），如何实现？

**决策：通过 MCP（Model Context Protocol）clone gitops-repo 到本地操作。**

```
开发者调用 /devops
    |
    v
AI 通过 MCP 执行 git clone gitops-repo → 本地临时目录
    |
    v
AI 在本地读取 platform-inventory.yaml、检查目录结构
    |
    v
AI 在本地创建/修改文件
    |
    v
AI 通过 MCP 执行 git commit + push + 创建 MR
```

**替代方案：**
- GitLab API 直接操作 → API 操作文件粒度太细（逐文件创建），批量操作复杂且容易部分失败
- 内嵌 Git 客户端 → Skill 是 AI prompt 文件，没有执行环境

**为什么选 MCP：** Skill 本质是 AI 的 prompt，没有自己的执行环境。MCP 提供标准化的工具调用接口，AI 通过 MCP 调用 git 命令就像开发者在终端操作一样，语义清晰，原子性好。

---

### D2: Skill 前置条件 — 三道检查门

**决策：Skill 执行前 SHALL 按顺序检查三个前置条件：**

| 检查项 | 条件 | 不满足时的行为 |
|--------|------|---------------|
| 1. MCP 可用 | MCP 已安装并配置 git 工具 | 提示并引导安装 MCP，停止执行 |
| 2. 代码仓库非空 | 当前仓库有实际代码文件（不仅是 README） | 提示"请先完成代码开发，再运行 /devops 初始化"，停止执行 |
| 3. 意图可识别 | AI 能理解用户的意图 | 追问具体意图 |

**为什么要求代码仓库非空：** init-service 的核心价值是 AI 分析已有代码自动推断信息（语言、端口、依赖）。空仓库无代码可分析，推断无从谈起，此时初始化无意义。

**MCP 引导流程：**
1. AI 检测 MCP 是否可用（尝试调用 MCP git 工具）
2. 不可用时，输出安装指引（安装命令 + 配置示例）
3. 用户安装后重新运行 `/devops`

---

### D3: init-service 流程设计 — 为已有代码初始化 DevOps 配置

**核心定位：** init-service 不是"创建服务"，而是"为已有代码仓库接入 DevOps 平台"。起点是开发者的代码仓库已经有实际代码。

**完整流程：**

```
步骤 1: AI 分析代码仓库
    ├── 检查代码语言（go.mod / pom.xml / package.json / requirements.txt）
    ├── 检查端口配置（从代码或配置文件推断）
    ├── 检查健康检查路径（从路由或框架推断）
    └── 检查已有依赖（import 路径、配置文件中的 DB/Redis/Kafka 引用）
    |
    v
步骤 2: AI 展示推断结果，逐项确认
    ├── 服务名：order-service（来源：目录名 / go.mod module）→ 确认？
    ├── 域：trade → 需要用户指定（AI 列出可用域）
    ├── 团队/负责人 → 需要用户指定
    ├── 语言：go → 确认？
    ├── 端口：8080 → 确认？
    ├── 健康检查：/healthz → 确认？
    ├── 慢启动：false（Java 时推荐 true）→ 确认？
    └── 依赖：检测到 MySQL 使用 → 是否添加为依赖？
    |
    v
步骤 3: 生成 .devops.yaml
    ├── 填充 service 字段（name/domain/team/owner）
    ├── 填充 gitops 字段（repo 从 platform-inventory.yaml 读取，path 自动生成）
    ├── 填充 runtime 字段（language/port/health_check/slow_start）
    └── 填充 dependencies 字段（初始化时可为空）
    |
    v
步骤 4: 通过 MCP clone 配置仓库，生成配置文件
    ├── 检查冲突（services/{domain}/{service}/ 是否已存在）
    ├── 创建 base/ 目录（deployment.yaml, service.yaml, ingress.yaml, kustomization.yaml）
    ├── 创建 overlays/{env}/ 目录（dev/test/staging/prod 各一个 kustomization.yaml）
    ├── 如有 owner 依赖 → 创建 resources/{domain}/{type}/{name}/ 目录
    └── 展示将要创建的完整文件列表和关键内容 → 用户确认
    |
    v
步骤 5: 提交变更
    ├── 创建 MR 到配置仓库（MR 描述含操作发起人、意图、影响范围）
    └── 同时在代码仓库创建 .devops.yaml 文件
    |
    v
步骤 6: CI 配置检查（见 D6）
    ├── 检查 .gitlab-ci.yml 是否存在
    ├── 检查是否包含部署步骤（更新配置仓库镜像 tag）
    └── 缺失或有问题 → 询问是否需要帮助生成/优化
    |
    v
步骤 7: 展示结果和下一步
    ├── 已创建的 MR 链接
    ├── .devops.yaml 已生成
    └── 下一步建议："MR 合并后，push 代码即可自动部署到 dev 环境"
```

**信息推断策略（减少用户输入）：**

| 信息 | 推断方式 | 推断失败时 |
|------|---------|-----------|
| 服务名 | 目录名 / go.mod module / package.json name | 让用户指定 |
| 语言 | go.mod=go, pom.xml=java, package.json=node, requirements.txt=python | 让用户指定 |
| 端口 | 代码中的 Listen / Server 配置 | 默认提示 8080，让用户确认 |
| 健康检查 | 路由中的 /health 或 /healthz | 默认 /healthz，让用户确认 |
| 依赖 | import 路径（database/sql → MySQL）、配置文件（redis://） | 初始化时可不添加 |

**为什么所有推断都要确认：** 遵循 P1（准确）原则。AI 推断可以减少用户输入量，但推断结果必须经用户确认才能写入。推断错误且未确认就写入是"静默出错"——违反底层原则。

---

### D4: Secret 管理方案 — Operator 自动生成 + 命名约定

**问题：** 服务创建 MySQL/Redis 依赖时，连接密码怎么传递给应用？

**决策：K8s 原生 Secret + Operator 自动生成 + 命名约定，AI 只写 secretRef 不接触密码值。**

```
Operator 创建中间件实例
    |
    v
Operator 自动生成 K8s Secret（遵循命名约定）
    |
    v
Secret name = {instance-name}-secret
    |
    v
AI 在 deployment overlay 中添加 envFrom: secretRef
    |
    v
Pod 启动时自动注入环境变量
```

**命名约定：**

| 中间件类型 | Secret 名称 | 包含的 key |
|-----------|------------|-----------|
| MySQL | `{instance-name}-secret` | `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` |
| Redis | `{instance-name}-secret` | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |
| Kafka | 无需 Secret | 通过 `KAFKA_BOOTSTRAP` 环境变量连接（集群内无认证） |

**AI 操作示例：**

```yaml
# AI 在 overlay 中添加的 envFrom（AI 只写这个，不接触密码值）
patches:
  - target:
      kind: Deployment
      name: order-service
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/envFrom
        value:
          - secretRef:
              name: order-db-secret
```

**业务 Secret 处理（第三方 API Key 等）：**

1. 开发者在 K8s 中手动创建 Secret（或通过 CI 变量注入）
2. 告知 AI Secret 名称
3. AI 在 overlay 中添加 secretRef 引用
4. AI 永远不会询问或存储密码值

**为什么选此方案（AI 不易出错原则）：**
- AI 只需要知道命名约定（`{instance-name}-secret`），不需要生成密码
- Secret 由 Operator 在集群内自动创建，不经过 Git 流程（密码不入 Git）
- 命名约定确定，AI 写 secretRef 时不会写错名字
- 替代方案（Vault、External Secrets Operator）增加了 AI 需要理解的组件和配置项，出错面增大

---

### D5: 资源规格方案 — S/M/L 预定义等级

**问题：** 创建服务时 CPU/内存配置怎么确定？

**决策：预定义 S/M/L 三个等级，超额走 MR 审批。**

| 等级 | CPU requests | CPU limits | Memory requests | Memory limits | 适用场景 |
|------|-------------|------------|-----------------|---------------|---------|
| S | 100m | 500m | 128Mi | 512Mi | 轻量级服务、sidecar |
| M | 250m | 1000m | 256Mi | 1Gi | 标准业务服务 |
| L | 500m | 2000m | 512Mi | 2Gi | 高负载服务 |

**AI 引导逻辑：**

```
AI: 请选择资源规格等级：
    S - 轻量级（CPU 100m-500m, 内存 128Mi-512Mi）
    M - 标准（CPU 250m-1000m, 内存 256Mi-1Gi）   ← 推荐
    L - 高负载（CPU 500m-2000m, 内存 512Mi-2Gi）

    如需超出 L 的配置，需要走额外审批流程。
```

**超额审批：**
- 开发者指定超出 L 的资源配置时，AI 创建的 MR 自动添加平台团队作为 reviewer
- MR 描述中注明"资源配置超出标准等级 L，需平台团队审批"
- 平台团队确认后合并 MR

**等级仅用于 init-service 时引导选择。** 后续调整资源配置时，开发者通过 `/devops` 指定具体值，AI 直接修改 overlay patch。超出 L 时同样触发平台团队审批。

**为什么预定义而非自由填写：**
- 减少 AI 和用户的决策负担——大多数场景 M 就够用
- 防止资源浪费——不了解需求的用户往往会填过大的值
- 保留灵活性——真正需要超额时有审批通道

---

### D6: CI 配置检查 — Skill 只检查，不生成

**问题：** init-service 时 .gitlab-ci.yml 怎么处理？

**决策：Skill 不主动生成 CI 配置。只在 init-service 最后一步检查 CI 配置合理性，缺失或有问题时询问开发者是否需要帮助。**

**CI 配置不是 Skill 的职责：** .gitlab-ci.yml 是开发者自己的编译测试流程，不同服务差异很大（语言、框架、测试策略各不同）。DevOps Skill 关注的是"代码构建完镜像后，配置仓库是否能被正确更新"。

**检查项：**

| 检查项 | 检查内容 | 异常时行为 |
|--------|---------|-----------|
| CI 文件存在 | .gitlab-ci.yml 是否存在 | 提示"未检测到 CI 配置，是否需要帮你生成基础框架？" |
| 部署步骤 | 是否有更新配置仓库镜像 tag 的步骤 | 提示"CI 配置中未检测到部署步骤，push 代码后不会自动触发 dev 部署。是否需要帮你添加？" |
| 镜像命名 | 镜像 tag 是否使用 git sha | 提示"建议使用 git sha 作为镜像 tag 以确保可追溯" |
| Harbor 推送 | 是否推送到正确的 Harbor 项目 | 提示"镜像推送地址应为 harbor.company.com/{domain}/{service}" |

**如果开发者请求帮助生成/优化：**
- AI 根据代码分析结果生成适合该服务的 CI 配置
- CI 配置中 MUST 包含：构建镜像 → 推送 Harbor → 更新配置仓库 dev overlay newTag
- 具体 CI 阶段定义参考 Change 3 规范（本 change 只保证部署步骤存在）

---

### D7: add-dependency 流程设计

**完整流程：**

```
步骤 1: AI 读取 .devops.yaml，确认服务已接入
    |
    v
步骤 2: 确认依赖类型
    AI: 要添加什么依赖？
    ├── MySQL 数据库
    ├── Redis 缓存
    └── Kafka topic
    |
    v
步骤 3: 确认角色
    ├── MySQL/Redis → owner（创建新实例）或 consumer（引用已有实例）
    └── Kafka topic → producer（创建新 topic）或 consumer（消费已有 topic）
    |
    v
步骤 4: 根据角色执行不同操作
    |
    ├── owner/producer:
    │   ├── 按命名规范生成资源名
    │   ├── 检查冲突（同名资源是否存在）
    │   ├── 在配置仓库创建 resources/{domain}/{type}/{name}/ 目录
    │   ├── 在 deployment overlay 添加 envFrom secretRef（MySQL/Redis）
    │   │   或 KAFKA_BOOTSTRAP 环境变量（Kafka）
    │   └── 更新 .devops.yaml 的 dependencies
    │
    └── consumer:
        ├── 验证目标资源在配置仓库中存在
        ├── 在 deployment overlay 添加环境变量引用
        ├── 如果是跨域依赖 → 额外提示确认
        └── 更新 .devops.yaml 的 dependencies
    |
    v
步骤 5: 展示变更方案 → 用户确认 → 创建 MR
```

**环境变量注入规则：**

| 依赖类型 | owner 操作 | consumer 操作 |
|---------|-----------|-------------|
| MySQL | envFrom: secretRef ({instance}-secret) | envFrom: secretRef ({instance}-secret) |
| Redis | envFrom: secretRef ({instance}-secret) | envFrom: secretRef ({instance}-secret) |
| Kafka | env: KAFKA_BOOTSTRAP (从 platform-inventory 获取) | env: KAFKA_BOOTSTRAP (从 platform-inventory 获取) |

**跨域 consumer 的域定位：**

.devops.yaml 的 dependencies 条目新增可选 `domain` 字段。同域引用时省略（默认为 service.domain），跨域引用时必填。AI 根据 domain 字段定位到 `resources/{target-domain}/{type}/{name}/` 验证资源存在。

**remove-dependency 流程：**

add-dependency 的逆操作。AI 识别"移除依赖"意图后：
- consumer：从 .devops.yaml 删除条目 + 从 overlay 移除环境变量引用
- owner：额外检查资源消费方（尽力检查 + 不确定就问），无消费方时连同资源目录一起删除

---

### D8: decommission 流程设计

**核心原则：** 下线是高危操作，Skill 的角色是引导和检查，不自动删除。

**完整流程：**

```
步骤 1: AI 读取 .devops.yaml，确认服务信息
    |
    v
步骤 2: 依赖影响分析（尽力检查 + 不确定就问）
    ├── 从 .devops.yaml 列出拥有的资源（role=owner/producer）
    ├── MySQL/Redis：搜索配置仓库 overlay 中的 secretRef 引用反查消费方
    ├── Kafka topic：无法从配置仓库确认 → 询问用户
    └── 展示检查结果
    |
    v
步骤 3: 分步处理
    |
    ├── 3a: 有 consumer 的资源 → 阻止删除
    │   AI: "以下资源有其他服务依赖，无法删除：
    │        - order-events (consumer: notification-service, analytics-service)
    │        请先让消费方移除依赖，或将资源所有权转移给其他服务"
    │
    ├── 3b: 无 consumer 的 owner 资源 → 逐个确认删除
    │   AI: "order-db 仅被本服务使用，确认删除？"
    │
    └── 3c: 服务配置文件 → 确认删除
        AI: "将删除 services/{domain}/{service}/ 目录（base + 所有 overlays），确认？"
    |
    v
步骤 4: 执行删除
    ├── 创建 MR 删除配置仓库中的相关文件（reviewer MUST 包含 Tech Lead）
    ├── 提示开发者删除代码仓库中的 .devops.yaml
    └── 提示开发者在代码仓库 CI 中移除配置仓库相关步骤
    |
    v
步骤 5: 展示结果
    ├── MR 链接
    ├── 待开发者手动处理的事项清单
    └── 注意事项："MR 合并后 ArgoCD 将自动清理 dev 环境资源。
         test/staging/prod 环境需要手动触发 sync 或等待 self-heal"
```

**跨域依赖通知：** 如果被阻止删除的 consumer 来自其他域，AI 应提示联系对方团队协调。

**依赖检查原则："尽力检查 + 不确定就问"**

AI 不需要全知全能的依赖图。利用配置仓库中已有的信息尽力检查（如 secretRef 反查），无法确认时直接询问用户。这符合 P1 原则（不确定就问 > 猜测），也避免了维护额外依赖追踪文件的复杂性。

---

## Risks / Trade-offs

**R1: MCP 依赖增加了入门门槛**
→ 开发者首次使用前需安装 MCP。缓解：Skill 在检测到 MCP 未配置时提供一键安装指引，降低操作难度。MCP 安装是一次性操作。

**R2: 代码分析推断准确率**
→ AI 推断语言/端口/依赖可能不准确。缓解：所有推断结果都要用户逐项确认（P1 原则），推断不准不影响正确性，只影响体验效率。

**R3: Secret 命名约定与 Operator 实现耦合**
→ 不同 Operator 生成 Secret 的 key 名可能不同。缓解：在 platform-spec.md 中固定命名约定，平台团队配置 Operator 时遵循此约定。如果 Operator 默认命名不同，通过 Operator 配置调整。

**R4: 资源规格等级可能不适合所有场景**
→ S/M/L 三档粒度较粗。缓解：保留超额审批通道，特殊需求走 MR 审批。后续可根据实际使用情况增加等级或调整参数。

**R5: decommission 后配置残留**
→ 开发者可能忘记删除代码仓库中的 .devops.yaml 和 CI 配置。缓解：Skill 在完成后给出清晰的待办清单；代码仓库 CI 中如果仍引用已删除的配置仓库路径，push 时会失败（大声失败）。

**R6: CI 配置检查覆盖面有限**
→ Skill 只检查关键项（部署步骤、镜像命名），无法覆盖所有 CI 配置问题。缓解：CI 配置的完整规范由 Change 3 定义，本 change 只做基本的"能跑通"检查。

**Trade-off: 推断 vs 询问**
推断能力越强，用户输入越少（P3 体验好），但推断错误的风险越大（P1 准确性下降）。本设计选择"推断 + 强制确认"——尽量推断但每项都确认，在不牺牲准确性的前提下改善体验。
