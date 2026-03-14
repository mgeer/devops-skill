## ADDED Requirements

### Requirement: 环境推进流程

AI SHALL 支持用户通过自然语言将服务推进到目标环境（test/staging/prod）。推进流程复用已有的 create-promotion-mr.sh 脚本。推进采用链式模型：test 的源是 dev，staging 的源是 test，prod 的源是 staging。

环境推进链：

| 目标环境 | 源环境 |
|---------|--------|
| test | dev |
| staging | test |
| prod | staging |

#### Scenario: 推进到 test

- **WHEN** 用户说"部署到 test"
- **THEN** AI SHALL：
  1. 从 gitops-repo 读取源环境（dev）overlay 的当前 image tag
  2. 从 gitops-repo 读取目标环境（test）overlay 的当前 image tag
  3. 展示"将 {source-tag} 推进到 test（当前 test 为 {target-tag}），确认？"
  4. 用户确认后，通过 MCP 调用 create-promotion-mr.sh
  5. 返回 MR 链接

#### Scenario: 推进到 staging

- **WHEN** 用户说"部署到 staging"
- **THEN** AI SHALL 从 test overlay 读取当前 tag 作为推进源，展示"将 {test-tag} 推进到 staging，确认？"，确认后创建 MR

#### Scenario: 目标环境已是最新

- **WHEN** 用户推进到目标环境，但目标环境 overlay 的 tag 已与源环境相同
- **THEN** AI SHALL 提示"{target-env} 环境已是最新版本（{tag}），无需推进"

#### Scenario: 推进到 prod

- **WHEN** 用户说"部署到生产"
- **THEN** AI SHALL 从 staging overlay 读取当前 tag 作为推进源，额外提醒"这是生产环境推进，MR 需要 Tech Lead 审批"，确认后创建 MR

#### Scenario: 用户尝试推进到 dev

- **WHEN** 用户说"部署到 dev"
- **THEN** AI SHALL 提示"dev 环境由 CI 自动部署，无需手动推进。push 代码到 main 分支后 CI 会自动更新。"

---

### Requirement: 回滚流程

AI SHALL 支持用户通过自然语言回滚目标环境到之前的版本。回滚本质是推进旧 tag，复用相同的 MR 机制。

#### Scenario: 回滚到上个版本

- **WHEN** 用户说"回滚 test"
- **THEN** AI SHALL：
  1. 从 gitops-repo 的 git history 中查找 test overlay 的上一个 image tag
  2. 展示"将 test 从 {current-tag} 回滚到 {previous-tag}，确认？"
  3. 用户确认后，通过 MCP 调用 create-promotion-mr.sh（使用旧 tag）
  4. 返回 MR 链接

#### Scenario: 回滚到指定版本

- **WHEN** 用户说"回滚 test 到 abc123"
- **THEN** AI SHALL 展示"将 test 从 {current-tag} 回滚到 abc123，确认？"，确认后创建 MR

#### Scenario: 回滚时展示版本历史

- **WHEN** 用户说"回滚 prod"但未指定目标版本
- **THEN** AI SHALL 从 git history 中列出最近 5 个版本供选择：
  ```
  最近的版本:
    1. abc123 (2 小时前)  ← 当前
    2. 7ef890 (1 天前)
    3. def456 (3 天前)
  回滚到哪个版本？
  ```

---

### Requirement: 推进/回滚时 migration 文件变更检测

AI SHALL 在推进或回滚时检测两个 tag 之间是否包含 migration 文件变更。检测仅在服务的 .devops.yaml 包含 `runtime.migration_path` 时执行。AI 只做信息搬运，不做安全判断。

#### Scenario: 推进时检测到 migration 变更

- **WHEN** 用户推进到目标环境，git diff {target-tag}..{source-tag} 在 `runtime.migration_path` 目录下有文件变更
- **THEN** AI SHALL 展示：
  ```
  本次推进包含以下数据库变更文件：
    - db/migration/V3__add_order_status.sql
    - db/migration/V4__create_index.sql

  AI 无法判断 schema 变更的兼容性，请你自行确认：
    1. 以上变更是否向后兼容？（旧版本代码能否在新 schema 上运行）
    2. 是否已在 dev 环境验证通过？

  确认继续推进？
  ```

#### Scenario: 回滚时提醒 schema 不回退

- **WHEN** 用户回滚 test，且本次部署包含 migration 文件变更
- **THEN** AI SHALL 展示：
  ```
  本次部署包含数据库 schema 变更，schema 不会回退。
  请确认旧版本代码兼容当前 schema。

  确认继续回滚？
  ```

#### Scenario: 无 migration_path 时跳过检测

- **WHEN** 用户推进到目标环境，但 .devops.yaml 不包含 `runtime.migration_path`
- **THEN** AI SHALL 跳过 migration 检测，直接进入确认步骤

#### Scenario: 无 migration 文件变更时不提醒

- **WHEN** 用户推进到目标环境，git diff 在 migration_path 目录下无文件变更
- **THEN** AI SHALL 不显示 migration 提醒，直接进入确认步骤
