## 1. 配置仓库初始化

- [x] 1.1 在 GitLab 创建 gitops-repo 仓库，初始化 README 和 .gitignore
- [x] 1.2 创建三层顶层目录结构（infrastructure/、resources/、services/、argocd/）
- [x] 1.3 创建 platform-inventory.yaml（填入集群、环境、域、命名规范、中间件、可观测性、镜像仓库、GitLab 配置）
- [x] 1.4 配置 CODEOWNERS（platform-inventory.yaml 和 infrastructure/ 需平台团队审批，resources/ 和 services/ 按域分配团队）
- [ ] 1.5 配置 main 分支 branch protection（仅 CI bot 和平台团队可直推，其他人走 MR）

## 2. Kustomize 模板与示例

- [x] 2.1 创建 services 示例：demo-service 的 base/（deployment.yaml、service.yaml、ingress.yaml、kustomization.yaml），遵循 base/overlay 内容边界规范，base deployment 包含 securityContext（runAsNonRoot、readOnlyRootFilesystem、allowPrivilegeEscalation:false）
- [x] 2.2 创建 services 示例：demo-service 的 overlays/（dev/test/staging/prod 各一个 kustomization.yaml），包含 namespace、images、patches
- [x] 2.3 创建 resources 示例：demo MySQL 实例的 base/instance.yaml + overlays/（dev 用默认值、prod 有 replicas patch）
- [x] 2.4 创建 resources 示例：demo Kafka topic 的 base/topic.yaml + overlays/（dev 1分区、prod 6分区）
- [x] 2.5 验证所有示例：对每个 overlay 执行 `kustomize build` 确认构建成功

## 3. ArgoCD 部署与配置

- [ ] 3.1 在 non-prod 和 prod 集群手动安装 ArgoCD（helm install）
- [ ] 3.2 配置 ArgoCD 连接 gitops-repo（添加 repo credential）
- [ ] 3.3 在 ArgoCD 中注册两个集群并打环境标签（non-prod: env=dev/test/staging，prod: env=prod）
- [x] 3.4 创建 argocd/appset.yaml — services ApplicationSet（matrix generator: git directories × clusters）
- [x] 3.5 创建 argocd/appset.yaml — resources ApplicationSet（matrix generator: git directories × clusters）
- [x] 3.6 配置 ApplicationSet 的同步策略（dev: auto-sync+selfHeal+prune，其他: selfHeal only）
- [ ] 3.7 验证：创建 demo-service overlay 后 ArgoCD 自动生成对应 Application

## 4. K8s 集群 namespace 与基础隔离

- [ ] 4.1 按 platform-inventory.yaml 中定义的域，创建所有 namespace（dev-trade、test-trade、staging-trade、prod-trade 等）
- [ ] 4.2 为每个 namespace 创建默认 deny-all NetworkPolicy（跨域隔离基础）
- [ ] 4.3 验证：同域不同环境的 namespace 之间默认不可访问

## 5. GitOps 联动凭证

- [ ] 5.1 在 GitLab 为 gitops-repo 创建 Deploy Token（scope: write_repository，设置 expiry）
- [ ] 5.2 在各代码仓库的 GitLab CI/CD 变量中配置 Deploy Token（protected variable）
- [ ] 5.3 在 GitLab 为 Harbor 创建 Robot Account（按 domain 隔离）
- [ ] 5.4 在各代码仓库的 GitLab CI/CD 变量中配置 Harbor Robot Account
- [ ] 5.5 验证：CI pipeline 能成功 clone 配置仓库、push 变更、推送镜像

## 6. CI 直推脚本

- [x] 6.1 编写 CI 脚本模板：clone 配置仓库 → 修改 dev overlay 的 newTag → commit → push（commit message 格式: `ci: update {service} image to {tag}`），包含 pull --rebase 重试逻辑（最多 3 次，处理并发冲突）
- [x] 6.2 编写 CI 脚本模板：创建 MR 到配置仓库（用于 test/staging/prod 推进，MR 描述含发起人、意图、影响范围）
- [x] 6.3 将脚本模板放入可复用位置（GitLab CI include 模板或共享 runner 脚本）
- [x] 6.4 编写配置仓库 CI 校验脚本：检测直推 commit 的 diff 范围，只允许修改 overlays/dev/ 的 images 字段，违规时告警通知平台团队
- [ ] 6.5 验证：demo-service push 代码 → CI 构建镜像 → 更新 dev overlay newTag → ArgoCD 自动部署到 dev
- [ ] 6.6 验证：两个服务同时 push，CI 并发直推配置仓库，确认 rebase-retry 逻辑正常工作

## 7. .devops.yaml schema 定义

- [x] 7.1 编写 .devops.yaml 的 JSON Schema 文件（用于校验 service/runtime/dependencies 字段，runtime 含 slow_start 可选字段）
- [x] 7.2 编写校验脚本：检查 service.domain 是否在 platform-inventory.yaml 的 domains 中
- [x] 7.3 编写校验脚本：检查 dependencies 中的 role 和 type 组合是否合法
- [x] 7.4 编写漂移检测脚本：对比 .devops.yaml 与配置仓库现状，输出差异
- [x] 7.5 在代码仓库 CI 中添加 .devops.yaml 变更提醒（检测到变更时输出"请运行 /devops 同步"）

## 8. Skill 骨架

- [x] 8.1 创建 devops-skill 仓库，初始化目录结构（skill.md、platform-spec.md、flows/、examples/）
- [x] 8.2 编写 skill.md 骨架：核心原则（P0-P3）、AI 处理逻辑框架（8步）、意图识别分类、platform-spec.md 引用
- [x] 8.3 编写 platform-spec.md：汇总本 change 所有规范（配置仓库结构、路径公式、命名规范、环境管理、GitOps 工作流、资源所有权模型、base/overlay 边界规则）
- [x] 8.4 在 platform-spec.md 中包含标准 Kustomize patch 模板（replicas、resources、env vars 等常见操作的固定 patch 模板，供 AI 复用）
- [x] 8.5 在 platform-spec.md 中包含 base deployment 标准模板（含 securityContext、probes、startupProbe 条件逻辑），以及重命名操作的标准流程说明

## 9. 端到端验证

- [ ] 9.1 用 demo-service 走完完整链路：创建 .devops.yaml → 生成配置仓库文件 → push 代码 → CI 构建 → dev 自动部署 → 创建 MR 推进到 test
- [ ] 9.2 验证命名规范：所有生成的资源名、namespace、label 符合 naming 规范
- [ ] 9.3 验证所有权模型：demo-service 拥有 MySQL 实例 + Kafka topic，另一个 demo-consumer 声明 consumer 引用
- [ ] 9.4 验证冲突检测：尝试创建同名服务，确认被拒绝
- [ ] 9.5 验证重命名流程：尝试重命名 demo-service，确认 AI 按"创建新 → 迁移 → 删除旧"三步执行
- [ ] 9.6 清理 demo 资源或保留为 examples/
