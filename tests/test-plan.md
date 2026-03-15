# /test-devops — DevOps Skill 行为测试

## 设计原则

1. **测行为，不测实现** — 每个测试对应一个用户可见的 skill 行为（如「初始化项目」），不单独测内部脚本或推断规则
2. **自验证 + 关键值抽查** — 用平台自己的 CI 脚本（validate-devops-yaml.sh、detect-drift.sh）做第一层验证，再抽查脚本覆盖不到的语义字段
3. **只测有行为差异的场景** — Go + Java 覆盖所有语言差异（Java 独有 slow_start），不重复测行为相同的 Node/Python
4. **报告驱动 review** — 跑完输出结构化报告，人工 review 关键文件附录

---

## 前置修复

### validate-devops-yaml.sh macOS 兼容性

`gitops-repo/schemas/validate-devops-yaml.sh` 第 36-37 行 `grep -oP` macOS 不支持：

```bash
# 原
TYPE=$(echo "${line}" | grep -oP 'type:\s*\K\S+' || true)
ROLE=$(echo "${line}" | grep -oP 'role:\s*\K\S+' || true)
# 改
TYPE=$(echo "${line}" | awk -F'type:' '{print $2}' | awk '{print $1}')
ROLE=$(echo "${line}" | awk -F'role:' '{print $2}' | awk '{print $1}')
```

---

## 行为测试清单

### 1. 初始化 Go 项目

完整的 init-service 端到端测试。

**Given:** `tests/fixtures/code-repos/go-service/`（含 MySQL + Kafka 信号 + migration 目录）

**When:** Claude 按 `flows/init-service.md` 执行推断 → 生成 .devops.yaml → 生成配置仓库文件

**Then:**

自验证（bash 硬判断）：
- `validate-devops-yaml.sh` → exit 0
- `detect-drift.sh` → exit 0（无漂移）

关键值抽查（Claude 检查，有明确预期值）：
| 字段 | 预期值 | 来源 |
|------|-------|------|
| language | go | go.mod |
| service name | order-service | go.mod module 最后一段 |
| port | 8080 | main.go ListenAndServe |
| health_check | /healthz | 路由注册 |
| slow_start | false | 非 Java |
| dependencies | mysql(owner) + kafka(producer) | import 检测 |
| migration_path | db/migration/ | V*.sql 扫描 |
| deployment: managed-by | devops-skill | 标签存在 |
| deployment: initContainers | flyway | 有 migration_path 触发 |
| prod: replicas | 3 | 环境差异化规则 |

### 2. 初始化 Java 项目

增量测试，仅验证 Java 特异行为。

**Given:** `tests/fixtures/code-repos/java-service/`（含 MySQL 信号）

**When:** Claude 按 `flows/init-service.md` 执行

**Then:**

自验证：
- `validate-devops-yaml.sh` → exit 0
- `detect-drift.sh` → exit 0

关键值抽查（仅验证 Java 独有的）：
| 字段 | 预期值 |
|------|-------|
| slow_start | true |
| deployment: startupProbe | 存在 |

### 3. 添加依赖

**Given:** 测试 1 生成的 .devops.yaml + 配置仓库文件

**When:** Claude 按 `flows/add-dependency.md` 添加 Redis consumer

**Then:**

自验证：
- `validate-devops-yaml.sh` → exit 0
- `detect-drift.sh` → exit 0

关键值抽查：
| 字段 | 预期值 |
|------|-------|
| .devops.yaml dependencies | 新增 redis consumer 条目 |
| .devops.yaml 原有依赖 | mysql + kafka 保持不变 |

### 4. 添加跨域依赖

**Given:** 测试 1 生成的 .devops.yaml（nrtk 域）

**When:** Claude 添加 biz-app 域的 Kafka topic consumer

**Then:**

关键值抽查：
| 字段 | 预期值 |
|------|-------|
| 新依赖条目 domain | biz-app |
| 资源引用路径 | resources/**biz-app**/kafka/... |
| 原有依赖 | 不变 |

### 5. 移除依赖

**Given:** 测试 3 的结果（含 mysql + kafka + redis）

**When:** Claude 按 `flows/remove-dependency.md` 移除 Redis

**Then:**

自验证：
- `validate-devops-yaml.sh` → exit 0

关键值抽查：
| 字段 | 预期值 |
|------|-------|
| .devops.yaml dependencies | redis 条目消失 |
| 原有依赖 | mysql + kafka 保持不变 |

### 6. 冲突检测

**Given:** 配置仓库中已存在 `services/nrtk/order-service/`

**When:** Claude 对另一个代码仓库执行 init-service，服务名也叫 order-service

**Then:**
- Claude 提示冲突（不静默覆盖）
- 不生成新文件

---

## 验证方法

```
两层验证互补，不重叠

┌─ 第一层：自验证（bash 硬判断）──────────────────────┐
│                                                     │
│  validate-devops-yaml.sh → 域名合法、type/role 组合  │
│  detect-drift.sh → 文件齐全、端口一致、资源目录存在   │
│                                                     │
│  确定性、可重复、覆盖结构层                           │
└─────────────────────────────────────────────────────┘

┌─ 第二层：关键值抽查（Claude 检查，明确预期值）────────┐
│                                                     │
│  推断正确性: language/port/deps 来源对不对            │
│  模板语义:   managed-by 标签、initContainers         │
│  环境差异化: prod replicas=3、资源规格上调             │
│  Java 特异:  slow_start + startupProbe               │
│                                                     │
│  覆盖脚本查不到的语义层                               │
└─────────────────────────────────────────────────────┘
```

---

## 测试报告格式

每次运行输出报告到 `tests/reports/YYYY-MM-DD-HHmm.md`。

### 报告结构

**第一段：汇总表**

| # | 行为测试 | 自验证 | 关键值 | 结果 |
|---|---------|--------|-------|------|
| 1 | 初始化 Go 项目 | ✓ | 10/10 | PASS |
| 2 | 初始化 Java 项目 | ✓ | 2/2 | PASS |
| 3 | 添加 Redis 依赖 | ✓ | 2/2 | PASS |
| 4 | 添加跨域 Kafka 依赖 | — | 3/3 | PASS |
| 5 | 移除依赖 | ✓ | 2/2 | PASS |
| 6 | 冲突检测 | — | 1/1 | PASS |
| **总计** | | | | **6/6 PASS** |

**第二段：逐项详情**

每个行为测试展示：推断结果对比表（预期 vs 实际）、自验证脚本输出、PASS/FAIL 状态。
失败时给出具体字段 + 预期值 vs 实际值。

**第三段：关键文件附录**

供人工 review。包含测试 1（Go 项目）生成的：
- .devops.yaml 完整内容
- deployment.yaml 关键片段（ports、probes、initContainers、labels）
- prod/kustomization.yaml 关键片段（replicas、resources）

---

## 交付物

```
tests/
├── test-plan.md                  # 本文件
├── test-devops/
│   └── SKILL.md                  # 测试 Skill 定义
├── fixtures/
│   ├── platform-inventory.yaml   # 平台配置（复制自 gitops-repo）
│   └── code-repos/
│       ├── go-service/           # Go 仓库（MySQL + Kafka + migration）
│       │   ├── go.mod
│       │   ├── main.go
│       │   └── db/migration/V1__init.sql
│       └── java-service/         # Java 仓库（MySQL + 慢启动）
│           ├── pom.xml
│           ├── src/main/resources/application.yml
│           └── src/main/java/com/example/App.java
└── reports/                      # 测试报告（git ignore）
    └── YYYY-MM-DD-HHmm.md
```

---

## 实施步骤

1. **修复 macOS 兼容性** — validate-devops-yaml.sh `grep -oP` → `awk`
2. **创建 fixture 文件** — Go + Java 代码仓库 + platform-inventory.yaml
3. **创建测试 Skill** — `tests/test-devops/SKILL.md`
4. **运行 `/test-devops` 验证全部通过**
