## 1. .devops.yaml schema 更新

- [x] 1.1 在 devops-yaml.schema.json 中新增 runtime.migration_path 可选字段（type: string）
- [x] 1.2 更新校验脚本：migration_path 有值时检查 dependencies 中是否有 mysql role=owner，不匹配则警告

## 2. Flyway init container 模板

- [x] 2.1 在 platform-spec.md 中新增 migration 执行规范章节（Flyway CLI、forward-only 策略、文件命名规范 V{version}__{description}.sql）
- [x] 2.2 在 platform-spec.md 中新增 init container 模板（Flyway 配置、Secret 引用、volume 挂载）
- [x] 2.3 更新 platform-spec.md 的 base deployment 模板：增加条件性 init container 生成逻辑（有 migration_path 时注入）

## 3. Deploy flow 编写

- [x] 3.1 编写 flows/deploy.md：推进流程（读取 dev/目标环境 tag → migration 检测 → 确认 → 调用脚本 → 返回 MR）
- [x] 3.2 编写 flows/deploy.md：回滚流程（查询版本历史 → 选择目标版本 → migration 提醒 → 确认 → 调用脚本 → 返回 MR）
- [x] 3.3 编写 flows/deploy.md：migration 文件变更检测逻辑（git diff 两个 tag 之间 migration_path 目录）
- [x] 3.4 编写 flows/deploy.md：推进时 migration 提醒措辞（信息搬运，明确责任在开发者）
- [x] 3.5 编写 flows/deploy.md：回滚时 schema 不回退提醒措辞

## 4. Skill 骨架更新

- [x] 4.1 更新 skill.md：意图识别表新增 deploy（部署/推进/上线/发布到）和 rollback（回滚/回退/恢复上个版本）意图
- [x] 4.2 更新 skill.md：意图识别表中 deploy 和 rollback 均指向 flows/deploy.md

## 5. Init-service flow 更新

- [x] 5.1 更新 flows/init-service.md：代码分析推断规则表新增 migration 路径推断（扫描 db/migration/、migrations/、sql/）
- [x] 5.2 更新 flows/init-service.md：.devops.yaml 生成模板中增加 runtime.migration_path 条件字段
- [x] 5.3 更新 flows/init-service.md：推断结果展示中增加 migration 路径项

## 6. 端到端验证

- [x] 6.1 验证场景 A：纯代码推进 — 无 migration_path 的服务推进到 test，确认无 migration 提醒
- [x] 6.2 验证场景 B：带 migration 推进 — 有 migration_path 的服务推进到 test，两个 tag 之间有 migration 文件变更，确认提醒正确
- [x] 6.3 验证场景 C：回滚 — 回滚包含 migration 变更的部署，确认 schema 不回退提醒正确
- [x] 6.4 验证场景 D：init-service migration 推断 — 代码仓库含 db/migration/ 目录，确认 AI 正确推断并写入 .devops.yaml
- [x] 6.5 验证场景 E：migration_path 有值但无 mysql owner 依赖，确认警告正确
