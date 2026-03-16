# Flow: deploy — 环境推进与回滚

## 触发条件
- 用户意图：部署、推进、上线、回滚、回退
- 前置条件：.devops.yaml 已存在

---

## 环境推进链

| 目标环境 | 源环境 |
|---------|--------|
| test | int |
| staging | test |
| prod | staging |

int 环境由 CI 自动部署，不支持手动推进。

---

## 推进流程

### Step 1: 确认目标环境

从用户消息中提取目标环境（test/staging/prod）。

```
用户: "部署到 int"
AI:   "int 环境由 CI 自动部署，无需手动推进。push 代码到 main 分支后 CI 会自动更新。"
      停止执行。

用户: "部署到 test"
AI:   目标环境 = test，源环境 = int
```

### Step 2: 读取当前 tag

通过 MCP 读取配置仓库：
- 源环境 overlay 的当前 image tag（`newTag` 字段）
- 目标环境 overlay 的当前 image tag

```
源环境（int）: abc123
目标环境（test）: 7ef890
```

如果两者相同 → 提示"{target-env} 环境已是最新版本（{tag}），无需推进"，停止执行。

### Step 3: Migration 文件变更检测

**仅当 `.devops.yaml` 包含 `runtime.migration_command` 时执行此步骤。**

在代码仓库中检测 migration 相关文件变更：
```bash
# 扫描常见 migration 目录（alembic/、db/migration/、migrations/、sql/）
git diff {target-tag}..{source-tag} --name-only -- alembic/ db/migration/ migrations/ sql/
```

**有变更时**，展示信息搬运式提醒：
```
本次推进包含以下数据库变更文件：
  - alembic/versions/001_init_schema.py
  - alembic/versions/002_add_index.py

AI 无法判断 schema 变更的兼容性，请你自行确认：
  1. 以上变更是否向后兼容？（旧版本代码能否在新 schema 上运行）
  2. 是否已在 dev 环境验证通过？

确认继续推进？
```

**无变更时**，跳过此步骤，不显示任何提醒。

**无 `migration_command` 时**，跳过此步骤。

### Step 4: 确认推进

```
将 {source-tag} 推进到 {target-env}（当前 {target-env} 为 {target-tag}）。
确认？
```

prod 环境额外提醒：
```
⚠️ 这是生产环境推进，MR 需要 Tech Lead 审批。
```

### Step 5: 执行推进

通过 MCP 调用 `create-promotion-mr.sh`：
- 创建分支 `promote/{service}-{env}-{tag}`
- 修改目标环境 overlay 的 `newTag`
- 创建 MR

### Step 6: 展示结果

```
✓ 推进 MR 已创建: {MR 链接}

  服务: {service}
  环境: {source-env} → {target-env}
  镜像: {tag}

MR 审批合并后，ArgoCD 将自动同步部署。
```

---

## 回滚流程

### Step 1: 确认目标环境和版本

从用户消息中提取目标环境和回滚版本。

```
用户: "回滚 test"           → 回滚到上个版本
用户: "回滚 test 到 abc123"  → 回滚到指定版本
用户: "回滚 prod"            → 展示版本历史供选择
```

### Step 2: 查询版本历史

通过 MCP 从配置仓库的 git history 中查找目标环境 overlay 的历史 tag：

```
最近的版本:
  1. abc123 (2 小时前)  ← 当前
  2. 7ef890 (1 天前)
  3. def456 (3 天前)
  4. 111aaa (5 天前)
  5. 222bbb (1 周前)

回滚到哪个版本？
```

如用户说"回滚到上个版本"，自动选择第 2 项。

### Step 3: Migration 提醒

**仅当 `.devops.yaml` 包含 `runtime.migration_command` 时执行此步骤。**

检查当前 tag 与回滚目标 tag 之间是否有 migration 文件变更：
```bash
git diff {rollback-tag}..{current-tag} --name-only -- alembic/ db/migration/ migrations/ sql/
```

**有变更时**，展示提醒：
```
本次部署包含数据库 schema 变更，schema 不会回退。
请确认旧版本代码兼容当前 schema。

确认继续回滚？
```

**无变更时**，跳过此步骤。

### Step 4: 确认回滚

```
将 {target-env} 从 {current-tag} 回滚到 {rollback-tag}。
确认？
```

### Step 5: 执行回滚

通过 MCP 调用 `create-promotion-mr.sh`（使用旧 tag），流程与推进完全一致。

### Step 6: 展示结果

```
✓ 回滚 MR 已创建: {MR 链接}

  服务: {service}
  环境: {target-env}
  回滚: {current-tag} → {rollback-tag}

MR 审批合并后，ArgoCD 将自动同步回滚。
```

---

## MR 创建规范

| 项目 | 推进 | 回滚 |
|------|------|------|
| 分支命名 | `promote/{service}-{env}-{tag}` | `rollback/{service}-{env}-{tag}` |
| commit message | `feat: promote {service} to {env}` | `feat: rollback {service} in {env}` |
| MR title | `feat: promote {service} to {env}` | `feat: rollback {service} in {env}` |
| MR reviewer | test: 域 owner / prod: Tech Lead | 同推进 |
