## ADDED Requirements

### Requirement: CI 直推 dev 环境

代码仓库 CI pipeline SHALL 在构建镜像成功后，直接 push 到配置仓库 main 分支更新 dev 环境的镜像 tag。

具体操作：
1. Clone 配置仓库
2. 修改 `services/{domain}/{service}/overlays/dev/kustomization.yaml` 中的 `images[].newTag`
3. Commit message 格式：`ci: update {service} image to {tag}`
4. Push 到 main 分支

#### Scenario: 代码 push 触发自动部署到 dev

- **WHEN** 开发者 push 代码到代码仓库 main 分支
- **THEN** CI SHALL 构建镜像、推送 Harbor、更新配置仓库 dev overlay 的 newTag 并 push 到 main，ArgoCD 自动同步到 dev 环境

#### Scenario: CI 直推仅限镜像 tag

- **WHEN** CI 更新配置仓库
- **THEN** CI MUST 只修改 `overlays/dev/kustomization.yaml` 中的 `images[].newTag` 字段，不得修改其他文件或字段

#### Scenario: CI 直推的 commit message

- **WHEN** CI 推送配置仓库变更
- **THEN** commit message SHALL 为 `ci: update {service} image to {tag}`，包含服务名和新镜像 tag

#### Scenario: CI 直推并发冲突

- **WHEN** 两个服务的 CI pipeline 同时尝试 push 到配置仓库 main 分支，第二个 push 遇到 git 冲突
- **THEN** CI 脚本 SHALL 自动执行 pull --rebase 后重试 push，最多重试 3 次。3 次均失败时 CI job 标记为失败并通知开发者

---

### Requirement: MR 流程（非 dev 环境）

test/staging/prod 环境的所有变更 SHALL 通过 MR 流程：AI 或 CI 创建 MR → 审批 → 合并 → ArgoCD 同步。

#### Scenario: 推进到 test 环境

- **WHEN** AI 需要部署服务到 test 环境
- **THEN** AI SHALL 创建 MR，修改 `overlays/test/kustomization.yaml` 的 newTag，MR 描述包含操作发起人、意图、影响的服务

#### Scenario: 推进到 prod 环境

- **WHEN** AI 需要部署服务到 prod 环境
- **THEN** AI SHALL 创建 MR，MR reviewer MUST 包含 Tech Lead 和 SRE，MR 描述 SHALL 包含 staging 环境的验证状态

#### Scenario: 修改部署配置（任何环境包括 dev）

- **WHEN** AI 需要修改 dev 环境的 replicas 或 resources limits
- **THEN** SHALL 通过 MR 流程，不得直推。只有镜像 tag 更新可以直推 dev

---

### Requirement: MR 描述规范

AI 创建的 MR MUST 包含以下信息以确保可追溯性：

| 字段 | 说明 |
|------|------|
| 操作发起人 | 谁触发了这个操作 |
| 操作意图 | AI 理解到的用户意图 |
| 影响的服务/资源 | 本次变更涉及哪些服务和资源 |
| 变更内容摘要 | 关键配置变更项 |
| 渲染结果 | `kustomize build` 的关键输出片段（可选） |

#### Scenario: 标准 MR 描述

- **WHEN** AI 为 order-service 创建部署到 staging 的 MR
- **THEN** MR 描述 SHALL 包含：发起人、"部署到 staging"意图、影响服务 order-service、变更内容（newTag 从 X 更新到 Y）

---

### Requirement: 凭证管理

CI 与配置仓库的交互 SHALL 使用 GitLab Deploy Token，配置在 CI/CD 变量中（protected）。

| 凭证 | 用途 | 存储位置 | 管理要求 |
|------|------|---------|---------|
| GitLab Deploy Token | CI 推送配置仓库 | GitLab CI 变量（protected） | 有 expiry，定期轮换 |
| Harbor Robot Account | CI 推送镜像 | GitLab CI 变量（protected） | 按 domain 隔离 |
| ArgoCD Repo Credential | ArgoCD 拉取配置仓库 | ArgoCD Secret（K8s） | 平台团队管理 |

#### Scenario: Deploy Token 用于 CI 直推

- **WHEN** CI 需要 push 到配置仓库
- **THEN** SHALL 使用 GitLab Deploy Token（scope: write_repository），不使用 SSH Key

#### Scenario: Deploy Token 过期

- **WHEN** Deploy Token 过期
- **THEN** CI 推送 SHALL 失败并报 401 错误，平台团队需在 GitLab 中重新生成 Token 并更新 CI 变量

---

### Requirement: ArgoCD ApplicationSet 自动发现

配置仓库 SHALL 包含一个 ApplicationSet 文件（`argocd/appset.yaml`），通过 Git directory generator + matrix generator 自动发现 services 和 resources。

#### Scenario: 新增服务自动被发现

- **WHEN** AI 在 `services/trade/order-service/overlays/dev/` 下创建了 kustomization.yaml
- **THEN** ApplicationSet SHALL 自动生成名为 `order-service-dev` 的 ArgoCD Application，目标 namespace 为 `dev-trade`

#### Scenario: 删除服务的 overlay 目录

- **WHEN** 某服务的 `overlays/staging/` 目录被删除
- **THEN** ApplicationSet SHALL 自动删除对应的 ArgoCD Application（如果 prune 开启）或标记为 OutOfSync

#### Scenario: AI 不修改 argocd/ 目录

- **WHEN** AI 执行任何服务或资源管理操作
- **THEN** AI MUST 不修改 `argocd/` 目录下的任何文件。ApplicationSet 通过目录结构自动发现，无需 AI 干预

---

### Requirement: ArgoCD 同步策略按环境区分

ArgoCD 的同步策略 SHALL 根据环境不同而不同：

| 环境 | Auto-Sync | Self-Heal | Prune |
|------|-----------|-----------|-------|
| dev | 开启 | 开启 | 开启 |
| test | 关闭 | 开启 | 关闭 |
| staging | 关闭 | 开启 | 关闭 |
| prod | 关闭 | 开启 | 关闭 |

#### Scenario: dev 环境自动同步

- **WHEN** 配置仓库 main 分支的 dev overlay 被更新（CI 直推）
- **THEN** ArgoCD SHALL 自动同步，将新镜像部署到 dev 环境

#### Scenario: prod 环境手动同步

- **WHEN** MR 合并到 main 分支，prod overlay 被更新
- **THEN** ArgoCD SHALL 标记该 Application 为 OutOfSync，等待人工在 ArgoCD UI 或 CLI 触发 sync

#### Scenario: 有人手动 kubectl 修改了集群

- **WHEN** 有人在 prod 集群中手动 `kubectl scale deployment` 修改了副本数
- **THEN** ArgoCD 的 Self-Heal SHALL 自动将副本数恢复到配置仓库中定义的值

---

### Requirement: 配置仓库 branch protection

配置仓库 main 分支 SHALL 配置 branch protection，限制谁可以直接 push。

#### Scenario: 允许 CI bot 直推

- **WHEN** CI bot（Deploy Token 身份）push 到 main 分支
- **THEN** SHALL 被允许（CI bot 在 allowed-to-push 列表中）

#### Scenario: 普通开发者直推被拒

- **WHEN** 普通开发者尝试直接 push 到配置仓库 main 分支
- **THEN** SHALL 被拒绝，必须通过 MR 流程

---

### Requirement: CI 直推范围校验

配置仓库 SHALL 通过 CI pipeline（push trigger）或 server-side hook 校验直推 commit 的变更范围，确保 CI bot 只能修改允许的文件和字段。

校验规则：
1. commit 的 diff 只涉及 `services/*/overlays/dev/kustomization.yaml` 或 `resources/*/overlays/dev/kustomization.yaml` 文件
2. diff 内容只包含 `images[].newTag` 或 `images[].newName` 字段的变更
3. 不符合规则的 commit SHALL 触发告警通知平台团队

#### Scenario: 合法的 CI 直推

- **WHEN** CI bot push 的 commit 只修改了 `services/trade/order-service/overlays/dev/kustomization.yaml` 中的 newTag
- **THEN** 校验 SHALL 通过

#### Scenario: CI 直推修改了非 dev overlay

- **WHEN** CI bot push 的 commit 修改了 `overlays/prod/kustomization.yaml`
- **THEN** 校验 SHALL 失败，触发告警通知平台团队"CI bot 修改了非 dev 环境配置，请检查 CI 脚本"

#### Scenario: CI 直推修改了 dev 的非镜像字段

- **WHEN** CI bot push 的 commit 修改了 `overlays/dev/kustomization.yaml` 中的 replicas patch
- **THEN** 校验 SHALL 失败，触发告警通知平台团队
