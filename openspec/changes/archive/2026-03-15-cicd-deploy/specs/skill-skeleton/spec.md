## MODIFIED Requirements

### Requirement: Skill 入口设计

/devops skill SHALL 提供两种调用方式：

1. `/devops` — 无参数，AI 自动检测当前上下文（代码仓库、.devops.yaml）并引导
2. `/devops <自然语言>` — 用户用自然语言描述意图

AI SHALL 识别以下意图类别：

| 意图关键词 | 操作类型 | 对应 flow |
|-----------|---------|----------|
| 初始化/接入/新建 | init-service | flows/init-service.md |
| 添加依赖/加数据库/加缓存/加消息队列 | add-dependency | flows/add-dependency.md |
| 移除依赖/不需要了/删除依赖 | remove-dependency | flows/remove-dependency.md |
| 下线/删除服务/退役 | decommission | flows/decommission.md |
| 部署/推进/上线/发布到 | deploy | flows/deploy.md |
| 回滚/回退/恢复上个版本 | rollback | flows/deploy.md |
| 检查CI/生成CI | ci-config-check | 内联处理 |

#### Scenario: 推进意图识别

- **WHEN** 开发者运行 `/devops 部署到 test`
- **THEN** AI SHALL 解析意图为 deploy，目标环境为 test，进入 deploy flow 的推进分支

#### Scenario: 回滚意图识别

- **WHEN** 开发者运行 `/devops 回滚 prod`
- **THEN** AI SHALL 解析意图为 rollback，目标环境为 prod，进入 deploy flow 的回滚分支

#### Scenario: 无参数调用 — 未接入

- **WHEN** 开发者在没有 .devops.yaml 的代码仓库中运行 `/devops`
- **THEN** AI SHALL 检查代码仓库是否有实际代码，有则引导 init-service 流程，无则提示"请先完成代码开发"

#### Scenario: 无参数调用 — 已接入

- **WHEN** 开发者在已有 .devops.yaml 的代码仓库中运行 `/devops`
- **THEN** AI SHALL 读取 .devops.yaml，检查配置仓库同步状态，主动引导下一步操作

#### Scenario: 意图不清晰

- **WHEN** 开发者运行 `/devops 帮我搞一下`
- **THEN** AI SHALL 追问"请描述您想做什么？例如：初始化服务、添加依赖、部署到某环境、回滚、下线服务"，不得猜测意图
