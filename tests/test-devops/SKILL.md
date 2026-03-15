# /test-devops — DevOps Skill 行为测试

你是 `/devops` skill 的测试执行者。你的任务是对 fixture 代码仓库执行 skill 的核心流程，验证输出正确性，生成测试报告。

**Input**: 可选参数指定测试范围。无参数则运行所有测试。

---

## 测试执行框架

### Step 1: 确定项目根目录和测试范围

```
PROJECT_ROOT = 当前工作目录（应为 devops 项目根目录）
FIXTURES = ${PROJECT_ROOT}/tests/fixtures
SCRIPTS_DIR = ${PROJECT_ROOT}/gitops-repo/schemas
FLOWS_DIR = ${PROJECT_ROOT}/devops-skill/flows
SPEC_FILE = ${PROJECT_ROOT}/devops-skill/platform-spec.md
INVENTORY = ${FIXTURES}/platform-inventory.yaml
```

根据参数确定范围：
- 无参数 / `all` → 运行全部 6 个行为测试
- `init` → 仅运行测试 1-2（init-service）
- `dep` → 仅运行测试 3-5（依赖操作）
- `conflict` → 仅运行测试 6（冲突检测）
- 数字 `1`-`6` → 运行指定编号的测试

### Step 2: 准备临时工作区

```bash
WORK_DIR=$(mktemp -d)
# 测试结束后清理
```

### Step 3: 逐个执行行为测试

对每个行为测试，按以下模式执行：

```
1. Setup — 准备输入（fixture 代码仓库、已有配置）
2. Execute — 按对应 flow 执行推断/生成
3. Verify — 自验证 + 关键值抽查
4. Record — 记录结果（PASS/FAIL + 详情）
5. Cleanup — 清理本次临时文件（保留报告数据）
```

### Step 4: 生成报告

将报告写入 `${PROJECT_ROOT}/tests/reports/YYYY-MM-DD-HHmm.md`。

---

## 行为测试定义

### 测试 1: 初始化 Go 项目

**Setup:**
- 读取 `${FIXTURES}/code-repos/go-service/` 下的所有文件
- 读取 `${FLOWS_DIR}/init-service.md` 了解推断规则
- 创建 `${WORK_DIR}/gitops-repo/` 作为模拟配置仓库

**Execute:**

按 `init-service.md` Step 2 的规则扫描 go-service：

1. **语言检测**: 检查 go.mod/pom.xml/package.json/requirements.txt
2. **服务名推断**: go.mod module 路径最后一段
3. **端口推断**: 搜索 ListenAndServe、http.Server 等模式
4. **健康检查推断**: 搜索路由注册中的 /health、/healthz、/ping、/ready
5. **慢启动推断**: 非 java → false
6. **依赖检测**: 搜索 database/sql、go-redis、kafka-go 等 import
7. **Migration 推断**: 扫描 db/migration/、migrations/、sql/ 中的 V*.sql

记录推断结果。

然后按 `init-service.md` Step 4 + Step 7 和 `platform-spec.md` §6 模板生成：
- `.devops.yaml`（假设 domain=nrtk, owner=test-user, 资源等级=M）
- 配置仓库文件（写入 `${WORK_DIR}/gitops-repo/`）

**Verify:**

第一层 — 自验证（bash 执行）：
```bash
${SCRIPTS_DIR}/validate-devops-yaml.sh ${WORK_DIR}/.devops.yaml ${INVENTORY}
# 预期: exit 0

${SCRIPTS_DIR}/detect-drift.sh ${WORK_DIR}/.devops.yaml ${WORK_DIR}/gitops-repo
# 预期: exit 0
```

第二层 — 关键值抽查（读取文件检查，每项有明确预期值）：

| 检查项 | 文件 | 预期值 |
|-------|------|-------|
| language | .devops.yaml | go |
| service name | .devops.yaml | order-service |
| port | .devops.yaml | 8080 |
| health_check | .devops.yaml | /healthz |
| slow_start | .devops.yaml | false |
| migration_path | .devops.yaml | db/migration/ |
| dependencies 含 mysql | .devops.yaml | type: mysql, role: owner |
| dependencies 含 kafka | .devops.yaml | type: kafka-topic, role: producer |
| managed-by 标签 | deployment.yaml | managed-by: devops-skill |
| initContainers | deployment.yaml | 含 flyway（因为有 migration_path + mysql owner）|
| prod replicas | prod/kustomization.yaml | 3 |

---

### 测试 2: 初始化 Java 项目

**Setup:**
- 读取 `${FIXTURES}/code-repos/java-service/`
- 复用测试 1 的配置仓库工作区（新建子目录）

**Execute:**
按 `init-service.md` Step 2 扫描 java-service，记录推断结果。
生成 .devops.yaml 和配置文件（假设 domain=nrtk, owner=test-user, 资源等级=M, service=payment-service）。

**Verify:**

自验证：
```bash
${SCRIPTS_DIR}/validate-devops-yaml.sh ${WORK_DIR}/.devops-java.yaml ${INVENTORY}
${SCRIPTS_DIR}/detect-drift.sh ${WORK_DIR}/.devops-java.yaml ${WORK_DIR}/gitops-repo-java
```

关键值抽查（仅验证 Java 独有行为）：

| 检查项 | 文件 | 预期值 |
|-------|------|-------|
| slow_start | .devops.yaml | true |
| startupProbe | deployment.yaml | 存在（含 initialDelaySeconds: 30）|

---

### 测试 3: 添加依赖

**Setup:**
- 使用测试 1 生成的 .devops.yaml 和配置仓库文件
- 读取 `${FLOWS_DIR}/add-dependency.md`

**Execute:**
按 `add-dependency.md` 流程，添加 Redis consumer 依赖：
- type: redis, role: consumer, name: shared-cache, domain: nrtk（同域）
- 更新 .devops.yaml 的 dependencies 数组
- 不创建资源目录（consumer 不拥有资源）

**Verify:**

自验证：
```bash
${SCRIPTS_DIR}/validate-devops-yaml.sh ${WORK_DIR}/.devops.yaml ${INVENTORY}
```

关键值抽查：

| 检查项 | 预期值 |
|-------|-------|
| dependencies 新增 redis | name: shared-cache, type: redis, role: consumer |
| 原有依赖不变 | mysql owner + kafka producer 仍在 |

---

### 测试 4: 添加跨域依赖

**Setup:**
- 使用测试 3 的 .devops.yaml（nrtk 域的 order-service）

**Execute:**
按 `add-dependency.md` 流程，添加跨域 Kafka consumer：
- type: kafka-topic, role: consumer, name: biz-app.user-service.registered, domain: biz-app

**Verify:**

关键值抽查：

| 检查项 | 预期值 |
|-------|-------|
| 新依赖 domain | biz-app（显式填写，因为跨域）|
| 新依赖 type | kafka-topic |
| 新依赖 role | consumer |
| 原有依赖不变 | mysql + kafka + redis 仍在 |

---

### 测试 5: 移除依赖

**Setup:**
- 使用测试 4 的 .devops.yaml（含 mysql, kafka, redis, 跨域 kafka）

**Execute:**
按 `remove-dependency.md` 流程，移除 Redis consumer（shared-cache）：
- 从 dependencies 中删除对应条目
- consumer 移除不涉及资源目录删除

**Verify:**

自验证：
```bash
${SCRIPTS_DIR}/validate-devops-yaml.sh ${WORK_DIR}/.devops.yaml ${INVENTORY}
```

关键值抽查：

| 检查项 | 预期值 |
|-------|-------|
| redis 条目 | 不存在 |
| 原有依赖不变 | mysql + kafka + 跨域 kafka 仍在 |

---

### 测试 6: 冲突检测

**Setup:**
- `${WORK_DIR}/gitops-repo/` 中已存在 `services/nrtk/order-service/`（测试 1 创建的）

**Execute:**
假设另一个代码仓库也叫 order-service，尝试初始化到 nrtk 域。
按 `init-service.md` Step 6 的冲突检测逻辑，检查 `services/nrtk/order-service/` 是否已存在。

**Verify:**

| 检查项 | 预期值 |
|-------|-------|
| 冲突检测结果 | 检测到冲突（目录已存在）|

---

## 报告格式

报告写入 `${PROJECT_ROOT}/tests/reports/YYYY-MM-DD-HHmm.md`，格式如下：

```markdown
# /test-devops 测试报告
生成时间: {timestamp}

## 汇总

| # | 行为测试 | 自验证 | 关键值 | 结果 |
|---|---------|--------|-------|------|
| 1 | 初始化 Go 项目 | ✓/✗ | N/N | PASS/FAIL |
| 2 | 初始化 Java 项目 | ✓/✗ | N/N | PASS/FAIL |
| 3 | 添加 Redis 依赖 | ✓/✗ | N/N | PASS/FAIL |
| 4 | 添加跨域 Kafka 依赖 | — | N/N | PASS/FAIL |
| 5 | 移除依赖 | ✓/✗ | N/N | PASS/FAIL |
| 6 | 冲突检测 | — | N/N | PASS/FAIL |

**总计: N/6 PASS**

## 详情

### 测试 N: {测试名} {PASS/FAIL}

**推断结果:**
| 字段 | 预期 | 实际 | 结果 |
|------|------|------|------|
| ... | ... | ... | ✓/✗ |

**自验证:**
- validate-devops-yaml.sh → exit {code} {✓/✗}
- detect-drift.sh → exit {code} {✓/✗}

**生成文件:** {N} 个

---
（每个测试重复此结构）

## 附录：关键生成文件

### .devops.yaml（测试 1 - Go 项目）
{完整文件内容}

### deployment.yaml 关键片段（测试 1）
{ports、probes、initContainers、labels 部分}

### prod/kustomization.yaml 关键片段（测试 1）
{replicas、resources 部分}
```

---

## 执行约束

- 所有文件操作在 `${WORK_DIR}`（/tmp 临时目录）中进行，不修改项目文件
- 生成配置时严格按 `platform-spec.md` §6 和 §7 的模板，不做创造性发挥
- 自验证脚本的退出码用 bash 获取，不猜测
- 关键值检查用读取文件后与预期值**精确比较**，不是"看起来合理"
- 测试结束后清理 WORK_DIR，仅保留报告文件
- 报告中附录部分包含实际生成的文件内容，供人工 review
