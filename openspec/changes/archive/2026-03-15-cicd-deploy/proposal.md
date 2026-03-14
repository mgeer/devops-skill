## Why

Change 1/2 完成了 CI 脚本模板（dev 直推、MR 推进、diff 校验）和服务生命周期管理，但缺少环境推进的 AI 交互流程和 DB migration 执行基础设施。开发者目前需要手动运行脚本推进环境、手动管理 schema 变更，且回滚时没有 migration 感知能力。

## What Changes

- 新增 `flows/deploy.md`：环境推进 + 回滚的 AI 交互流程（一个 flow 覆盖两个方向）
- 新增 DB migration 执行基础设施：Flyway CLI init container 模板，按需注入 deployment
- `.devops.yaml` 新增 `runtime.migration_path` 字段：有值则启用 init container，无则不加
- 推进时检测 migration 文件变更（git diff 两个 tag 之间），信息搬运式提醒开发者确认兼容性
- 回滚时提醒 schema 不会回退（forward-only，不支持 DOWN migration），要求开发者确认旧代码兼容当前 schema
- `platform-spec.md` 补充 migration 执行规范

## Capabilities

### New Capabilities
- `deploy-flow`: 环境推进与回滚的 AI 交互流程，包含 migration 文件变更检测和提醒
- `db-migration-infra`: DB migration 执行基础设施，Flyway CLI init container 模板及 .devops.yaml 集成

### Modified Capabilities
- `devops-yaml-schema`: 新增 `runtime.migration_path` 可选字段
- `skill-skeleton`: 意图识别新增 deploy/rollback 意图分类
- `init-service`: init-service 流程中增加 migration_path 推断逻辑

## Impact

- `devops-skill/flows/deploy.md` — 新增文件
- `devops-skill/platform-spec.md` — 补充 migration 执行规范章节
- `devops-skill/skill.md` — 意图分类新增 deploy/rollback
- `devops-skill/flows/init-service.md` — 增加 migration_path 推断步骤
- `gitops-repo/schemas/devops-yaml.schema.json` — 新增 migration_path 字段
- 服务 deployment.yaml base 模板 — 条件性增加 Flyway init container
