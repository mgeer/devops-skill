## MODIFIED Requirements

### Requirement: AI 处理逻辑框架

AI 收到用户输入后 SHALL 按以下顺序处理：

```
1. 检查 MCP 可用性（不可用则引导安装并停止）
2. 解析意图（自然语言 → 操作类型）
3. 检查代码仓库状态（是否有实际代码、是否已有 .devops.yaml）
4. 读取上下文（.devops.yaml + platform-inventory.yaml）
5. 检查前置条件（域是否存在、中间件是否可用、资源是否冲突）
6. 收集必要信息（逐个确认，不猜测）
7. 生成操作方案（展示将要做的变更）
8. 用户确认
9. 执行操作（生成 YAML / 创建 MR）
10. 展示结果（做了什么、下一步建议）
```

#### Scenario: MCP 不可用

- **WHEN** 用户运行 `/devops`，但 MCP 未安装或未配置 git 工具
- **THEN** AI SHALL 在步骤 1 停止，输出 MCP 安装指引，提示"安装完成后重新运行 /devops"

#### Scenario: 前置条件不满足

- **WHEN** 用户请求创建 MySQL 实例，但 platform-inventory.yaml 中 mysql.available=false
- **THEN** AI SHALL 在步骤 5 停止，提示"MySQL 尚未在平台上线，请联系平台团队"

#### Scenario: 收集信息阶段

- **WHEN** 用户请求"新建一个服务"但未提供服务名
- **THEN** AI SHALL 在步骤 6 询问"请提供服务名称"，不得自行生成

---

### Requirement: Skill 入口设计

/devops skill SHALL 提供两种调用方式：

1. `/devops` — 无参数，AI 自动检测当前上下文（代码仓库、.devops.yaml）并引导
2. `/devops <自然语言>` — 用户用自然语言描述意图

AI SHALL 识别以下意图类别：

| 意图关键词 | 操作类型 | 对应 flow |
|-----------|---------|----------|
| 初始化/接入/新建 | init-service | flows/init-service.md |
| 添加依赖/加数据库/加缓存/加消息队列 | add-dependency | flows/add-dependency.md |
| 移除依赖/不需要了/删除依赖 | remove-dependency | flows/add-dependency.md |
| 下线/删除服务/退役 | decommission | flows/decommission.md |
| 部署/推进/上线 | deploy | flows/deploy.md (Change 3) |
| 检查CI/生成CI | ci-config-check | 内联处理 |

#### Scenario: 无参数调用 — 未接入

- **WHEN** 开发者在没有 .devops.yaml 的代码仓库中运行 `/devops`
- **THEN** AI SHALL 检查代码仓库是否有实际代码，有则引导 init-service 流程，无则提示"请先完成代码开发"

#### Scenario: 无参数调用 — 已接入

- **WHEN** 开发者在已有 .devops.yaml 的代码仓库中运行 `/devops`
- **THEN** AI SHALL 读取 .devops.yaml，检查配置仓库同步状态，主动引导下一步操作

#### Scenario: 自然语言调用

- **WHEN** 开发者运行 `/devops 我要加一个 Redis 缓存`
- **THEN** AI SHALL 解析意图为 add-dependency，依赖类型为 Redis，进入 add-dependency 流程

#### Scenario: 意图不清晰

- **WHEN** 开发者运行 `/devops 帮我搞一下`
- **THEN** AI SHALL 追问"请描述您想做什么？例如：初始化服务、添加依赖、部署到某环境、下线服务"，不得猜测意图
