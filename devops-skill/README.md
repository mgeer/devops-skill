# /devops Skill

DevOps 平台 AI 操作员。开发者通过 `/devops` 管理 Kubernetes 服务的部署生命周期（初始化接入、添加依赖、部署、回滚、下线等），所有变更通过 GitOps 配置仓库完成，不直接操作集群。

## 前置条件

- MCP git 工具已配置（skill 通过 MCP 操作 GitOps 配置仓库）
- GitOps 配置仓库已就绪（见下方"平台管理员设置"）

## 平台管理员设置

### 还没有 GitOps 仓库

1. 在 GitLab 创建空仓库（如 `infra/gitops-repo`）
2. 将 `gitops-template/` 目录的内容提交到该仓库
3. 编辑 `platform-config.yaml`，填写所有必填字段
4. 按实际环境修改 `platform-inventory.yaml` 中的示例值（集群地址、域、命名规范等）
5. 运行 `/devops`，skill 会校验配置并引导完成后续设置

### 已有 GitOps 仓库

1. 将 `gitops-template/platform-config.yaml` 复制到仓库根目录
2. 填写必填字段
3. 运行 `/devops`，skill 会引导后续操作

## gitops-template/ 目录结构

```
platform-config.yaml      # 平台基础配置（GitLab、Harbor、Kafka 地址）
platform-inventory.yaml   # 集群、环境、域、命名规范定义
CODEOWNERS                # GitLab MR 审批规则
argocd/                   # ArgoCD ApplicationSet 模板
ci-templates/             # CI 脚本（镜像 tag 更新、promotion MR）
schemas/                  # .devops.yaml 校验与漂移检测
```

## 开发者使用

直接运行 `/devops` 并描述你的意图即可，例如：

- "初始化服务接入"
- "添加 MySQL 依赖"
- "部署到 test 环境"
- "回滚到上个版本"

Skill 会自动引导完成操作。
