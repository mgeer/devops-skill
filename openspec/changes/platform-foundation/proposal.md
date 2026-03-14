## Why

公司需要一套基于 GitLab + ArgoCD 的 DevOps 平台，以 AI Skill（/devops）作为交互界面。当前缺少统一的平台规范，导致服务接入方式不一致、依赖管理混乱、环境差异不可控。本 change 定义平台的"地基"——整体架构、配置仓库结构、命名规范、环境管理、GitOps 工作流——后续所有 change 都在这个框架内工作。

## What Changes

- 定义配置仓库三层结构（infrastructure / resources / services），按业务域组织
- 定义 .devops.yaml schema（服务的 DevOps 身份证，放在代码仓库）
- 定义 platform-inventory.yaml schema（平台能力清单，含集群、域、命名规范、中间件、可观测性）
- 确定配置管理方式：infrastructure 用 Helm，services/resources 用 Kustomize overlay
- 确定集群拓扑：两集群（非生产 + 生产），四环境（dev/test/staging/prod）
- 确定 namespace 策略：{env}-{domain}，跨域默认拒绝 + 显式声明允许
- 确定 ArgoCD 组织方式：ApplicationSet 自动发现
- 确定 GitOps 联动机制：dev 环境 CI 直推，test/staging/prod 走 MR 审批
- 确定资源管理规则：所有权模型、资源定义与依赖引用分离
- 定义命名规范：服务名、资源名、namespace、label
- 产出 skill.md 骨架（核心原则 + AI 处理逻辑，不含具体 flow）

## Capabilities

### New Capabilities
- `gitops-repo-structure`: 配置仓库三层目录结构规范（infrastructure/resources/services），按业务域组织，含 ArgoCD ApplicationSet 自动发现
- `devops-yaml-schema`: .devops.yaml 文件规范，定义服务基本信息、运行时配置、依赖声明，作为 AI 的输入源
- `platform-inventory-schema`: platform-inventory.yaml 文件规范，定义集群、环境、业务域、命名规范、中间件能力、可观测性栈，作为 AI 的平台知识来源
- `environment-management`: 四环境（dev/test/staging/prod）+ 两集群（非生产/生产）的管理规范，含环境推进策略和 Kustomize overlay 方案
- `naming-convention`: 全平台命名规范（服务名、资源名、namespace、Kafka topic、label），确保 AI 生成的命名全局一致
- `resource-ownership`: 资源所有权模型和依赖引用机制，定义谁拥有资源、怎么引用共享资源、删除时如何检查影响
- `gitops-workflow`: GitOps 工作流联动规范，定义 CI 如何更新配置仓库（dev 直推/其他走 MR）、凭证管理、ArgoCD 同步策略
- `skill-skeleton`: /devops skill 的骨架，定义核心原则（安全>准确>可追溯>体验）、AI 处理逻辑、意图识别框架

### Modified Capabilities
（无，这是全新平台的地基）

## Impact

- **配置仓库**：从零创建 gitops-repo 的完整目录结构和核心配置文件
- **代码仓库**：每个服务需要添加 .devops.yaml 文件
- **ArgoCD**：需要配置 ApplicationSet 规则
- **CI/CD**：需要配置 GitLab Deploy Token 或 SSH Key 用于联动配置仓库
- **K8s 集群**：需要创建 namespace 和基础 NetworkPolicy
- **团队影响**：平台团队需要理解三层结构和职责边界，业务团队需要了解 .devops.yaml 的作用
- **Skill 仓库**：创建 devops-skill 仓库，包含 skill.md 骨架和 platform-spec.md
