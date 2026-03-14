## Why

Change 1（平台基础规范）定义了配置仓库结构、命名规范、环境管理、GitOps 工作流等"地基"。但开发者还无法真正使用平台——缺少"如何将已有服务接入平台"、"如何管理中间件依赖"、"如何安全下线服务"的完整交互流程。本 change 设计开发者最核心的三个日常操作场景，并解决 Secret 管理和资源规格两个前置决策，使平台具备端到端可用性。

## What Changes

- 设计 init-service flow：为已有代码仓库初始化 DevOps 配置（.devops.yaml + 配置仓库文件），AI 分析代码推断信息、检查 CI 配置合理性
- 设计 add-dependency flow：为已接入服务添加/引用中间件依赖，AI 同步 .devops.yaml 变更到配置仓库
- 设计 decommission flow：服务下线与资源清理，含依赖检查和分步引导
- 确定 Secret 管理方案：K8s 原生 Secret + Operator 自动生成 + 命名约定，AI 只写 secretRef 不接触密码值
- 确定资源规格方案：预定义等级（S/M/L）+ 超额走 MR 审批
- 确定 Skill 操作配置仓库方式：通过 MCP clone gitops-repo 到本地操作
- 确定 Skill 前置条件：MCP 已配置、代码仓库非空、有实际代码
- 定义 CI 配置检查规范：AI 检查 .gitlab-ci.yml 是否包含部署步骤，缺失或有问题时引导生成/优化

## Capabilities

### New Capabilities
- `init-service`: 为已有代码仓库初始化 DevOps 配置的完整交互流程。包括代码分析、信息推断与确认、.devops.yaml 生成、配置仓库文件生成（MR）、CI 配置检查与引导
- `add-dependency`: 为已接入服务添加或移除中间件依赖的交互流程。包括依赖类型选择、owner/consumer 判断、资源创建或引用、移除依赖（含消费方检查）、配置仓库同步
- `decommission`: 服务下线与资源清理的交互流程。包括依赖影响检查、分步清理引导、跨域依赖通知
- `secret-management`: Secret 管理规范。定义 Operator 自动生成 Secret 的命名约定、envFrom 注入方式、业务 Secret 的处理流程
- `resource-quota`: 资源规格等级定义（S/M/L）和超额审批机制。定义各等级的 CPU/内存配置、AI 如何引导选择、超额时 MR 审批流程
- `ci-config-check`: CI 配置检查规范。定义 AI 检查 .gitlab-ci.yml 的检查项（部署步骤、镜像命名、Harbor 推送）、异常时的引导策略

### Modified Capabilities
- `devops-yaml-schema`: 新增 gitops 字段（repo + path），初始化时由 AI 自动填充；dependencies 新增可选 domain 字段（跨域引用时必填）
- `skill-skeleton`: 新增 MCP 前置检查、代码仓库非空检查、init-service/add-dependency/remove-dependency/decommission 意图识别

## Impact

- **代码仓库**：每个服务新增 .devops.yaml（含 gitops 字段）；AI 可能辅助生成/优化 .gitlab-ci.yml
- **配置仓库**：init-service 时批量创建 services/{domain}/{service}/ 和 resources/{domain}/ 目录及文件（通过 MR）
- **Skill 仓库**：新增 flows/init-service.md、flows/add-dependency.md、flows/decommission.md；更新 skill.md（新增意图分类和 MCP 检查）；更新 platform-spec.md（新增 Secret 命名约定和资源规格定义）
- **K8s 集群**：Operator 创建中间件实例时自动生成 Secret，应用通过 envFrom 引用
- **团队影响**：开发者学习 `/devops` 初始化流程；平台团队定义 S/M/L 资源规格标准
- **MCP 依赖**：开发者需安装并配置 MCP（git 操作），Skill 首次运行时引导
