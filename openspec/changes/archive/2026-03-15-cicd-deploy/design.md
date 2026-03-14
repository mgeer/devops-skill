## Context

Change 1 已完成 CI 基础设施（dev 直推脚本 update-dev-tag.sh、环境推进 MR 脚本 create-promotion-mr.sh、直推校验脚本 validate-direct-push.sh），Change 2 已完成服务生命周期管理（init-service、add-dependency、decommission）。

当前状态：
- dev 环境部署全自动（CI 直推 + ArgoCD auto-sync）
- test/staging/prod 环境需手动运行脚本推进
- DB schema 变更无标准化管理，开发者各自处理
- 回滚没有 migration 感知

## Goals / Non-Goals

**Goals:**
- 提供环境推进与回滚的 AI 交互流程，将"手动跑脚本"变为"对 AI 说一句话"
- 标准化 DB migration 执行方式（Flyway CLI init container），按需启用
- 推进/回滚时检测 migration 文件变更，信息搬运式提醒开发者确认兼容性
- init-service 时自动推断 migration 目录并记录到 .devops.yaml

**Non-Goals:**
- 不管 migration SQL 的编写（开发者职责）
- 不判断 schema 变更是否向后兼容（AI 无法判断，责任在开发者）
- 不支持 DOWN migration（forward-only 策略）
- 不管 CI pipeline 内部阶段设计（已由 Change 1 的 ci-config-check 覆盖）
- 不做多语言 migration 工具适配（默认 Flyway CLI，后续按需扩展）

## Decisions

### 1. Migration 工具：Flyway CLI

**选择：** 统一使用 Flyway CLI，跨语言执行纯 SQL migration。

**替代方案：**
- 各语言用自己的工具（golang-migrate / Alembic / Prisma）→ 每种语言一套模板，维护成本高
- 统一入口命令（make migrate）→ 灵活但没有真正标准化

**理由：** 一套 init container 模板覆盖所有语言，migration 文件就是纯 SQL，降低平台维护成本。

### 2. Migration 策略：Forward-only，无 DOWN

**选择：** 不要求也不支持 DOWN migration。回滚时只回退代码，schema 保持现状。

**理由：**
- DOWN migration 在实践中极少被测试，真正需要时往往不可用
- 强制 forward-only 促使开发者写向后兼容的 migration（expand-contract 模式）
- 简化平台实现——不需要 DOWN 执行逻辑

### 3. 执行方式：Init Container，按需注入

**选择：** 在 deployment 中添加 Flyway init container，仅当 .devops.yaml 包含 `runtime.migration_path` 时才注入。

**替代方案：**
- CI 阶段执行 → 与部署解耦，migration 可能在部署前很久执行，不够及时
- 应用启动时自执行 → 多副本并发启动时有竞争问题

**理由：** Init container 保证"先 migrate 再启动"的顺序，Flyway 内置锁机制处理多副本并发。

### 4. Migration 路径：AI 推断 + 记入 .devops.yaml

**选择：** init-service 时 AI 扫描常见 migration 目录（db/migration/、migrations/、sql/），推断后记入 `runtime.migration_path`。有值则注入 init container，无值则不加。

**理由：** migration_path 既是 init container 的配置来源，也是开启/关闭 migration 的开关，一个字段两个用途。

### 5. Deploy flow：薄流程，推进+回滚合一

**选择：** deploy flow 覆盖推进和回滚两个方向，核心是调用已有的 create-promotion-mr.sh 脚本，加上 migration 文件变更检测。

**理由：** 推进和回滚的机制完全一样（改 overlay newTag），只是方向不同。拆成两个 flow 没有必要。

### 6. Migration 提醒原则：信息搬运，不做安全判断

**选择：** AI 只列出变更的 migration 文件名，明确声明"AI 无法判断兼容性"，责任在开发者。

**理由：** 如果 AI 的提醒暗示"已检查安全"，会给开发者虚假安全感。明确边界比模糊安慰更负责。

### 7. DB 连接信息：复用已有 Secret

**选择：** Flyway init container 通过 secretKeyRef 逐字段引用 `{instance-name}-secret`（MYSQL_HOST/PORT/DATABASE/USER/PASSWORD），将 MYSQL_* 映射为 Flyway 所需的 FLYWAY_URL/USER/PASSWORD 环境变量。

**理由：** 复用 Operator 生成的 Secret，不引入新的 Secret 管理方式。使用 secretKeyRef 而非 envFrom，因为需要将 MYSQL_* 字段映射为 FLYWAY_* 格式。

## Risks / Trade-offs

- **[Flyway 锁竞争]** 多副本同时启动时，所有 init container 竞争 Flyway 锁 → 仅第一个执行 migration，其余等待后跳过。Flyway 内置机制处理，无需额外干预。
- **[Migration 路径不标准]** 开发者可能把 migration 文件放在非常规目录 → AI 推断失败时询问用户，不会静默跳过。
- **[Forward-only 风险]** 如果开发者写了不兼容的 migration（如 dropColumn），回滚代码后旧代码会崩 → 这是开发者的责任，AI 在推进时已提醒确认兼容性。
- **[Flyway 版本兼容]** Flyway 镜像版本需要与目标数据库版本兼容 → init container 使用固定版本标签，平台统一管理。
