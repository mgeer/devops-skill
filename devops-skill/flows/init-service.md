# Flow: init-service — 为已有代码接入 DevOps 平台

## 触发条件
- 用户意图：初始化、接入、创建服务
- 前置条件：代码仓库非空 + 无 .devops.yaml

---

## 完整流程

### Step 1: 前置检查

```
检查项          | 条件                          | 不满足时
MCP 可用        | MCP git 工具可调用              | 输出安装指引，停止
代码仓库非空     | 存在实际代码文件（非仅 README）    | 提示"请先完成代码开发"，停止
无 .devops.yaml | .devops.yaml 不存在             | 提示"已初始化，请用其他命令"，停止
```

### Step 2: 代码分析与推断

AI 扫描代码仓库，按以下规则推断信息：

#### 语言检测
| 文件 | 推断结果 |
|------|---------|
| `go.mod` | go |
| `pom.xml` 或 `build.gradle` | java |
| `package.json` | node |
| `requirements.txt` 或 `pyproject.toml` | python |
| 以上都无 | 让用户指定 |

#### 服务名推断
按优先级尝试：
1. `go.mod` 的 module 路径最后一段
2. `package.json` 的 name 字段
3. 当前目录名
4. 推断失败 → 让用户指定

服务名 MUST 匹配 `^[a-z][a-z0-9-]{1,39}$`，不匹配时自动转换（大写→小写、下划线→连字符）并让用户确认。

#### 端口推断
| 语言 | 搜索模式 | 默认值 |
|------|---------|-------|
| go | `ListenAndServe`、`http.Server{...Addr`、环境变量 `PORT` | 8080 |
| java | `server.port` in application.yml/properties | 8080 |
| node | `app.listen`、`server.listen`、`PORT` | 3000 |
| python | `uvicorn`/`gunicorn` 参数、Flask `app.run` | 8000 |

推断失败 → 提示默认值，让用户确认。

#### 健康检查推断
搜索路由注册中的 `/health`、`/healthz`、`/ping`、`/ready`。
推断失败 → 默认 `/healthz`，让用户确认。

#### 慢启动推断
- java → 推荐 `slow_start: true`（Spring Boot 启动慢）
- 其他 → 默认 `false`

#### 依赖检测
| 模式 | 推断结果 |
|------|---------|
| `database/sql`、`gorm`、`mysql` driver import | MySQL 依赖 |
| `go-redis`、`redis://`、`RedisTemplate` | Redis 依赖 |
| `kafka-go`、`sarama`、`KafkaTemplate`、`confluent-kafka` | Kafka 依赖 |

依赖检测结果仅作为建议，由用户确认是否添加。初始化时可以不添加依赖。

#### Migration 推断
扫描已有的 migration 配置：

| 语言 | 扫描目标 | 推断 migration_command |
|------|---------|----------------------|
| python | `alembic.ini` 或 `alembic/` 目录 | `alembic upgrade head` |
| java | `db/migration/V*.sql` 或 `src/main/resources/db/migration/` | `flyway migrate`（工具已在 jar 中） |
| go | `migrations/` 目录含 `*.sql` 文件 | `migrate -path /app/migrations -database $DATABASE_URL up` |
| node | `migrations/` 目录或 `knexfile.js` | `npx knex migrate:latest` |

推断逻辑：
- 找到匹配 → 推断 `migration_command`，展示并让用户确认
- 未找到 + 有 MySQL owner 依赖 → **主动提示**："检测到 MySQL owner 依赖但未发现 migration 配置。建议设置 DB migration，部署时自动初始化和更新数据库 schema。是否需要设置？"
  - 用户同意 → 根据语言推荐默认 command（如 Python 推荐 `alembic upgrade head`），让用户确认
  - 用户拒绝 → 不设置，继续
- 未找到 + 无 MySQL 依赖 → 不询问

### Step 3: 展示推断结果，逐项确认

```
我分析了你的代码仓库，以下是推断结果：

  服务名:      order-service（来源: go.mod）
  语言:        go
  端口:        8080（来源: main.go ListenAndServe）
  健康检查:    /healthz（来源: 路由注册）
  慢启动:      false
  Migration:   alembic upgrade head（来源: 检测到 alembic/ 目录）

  检测到的依赖:
    - MySQL（来源: database/sql import）
    - Kafka（来源: kafka-go import）

请逐项确认或修改。

接下来需要你提供：
  域: [从 platform-inventory.yaml 列出可用域]
    - nrtk
    - ppp-rtk
    - biz-app
    - bigdata
    - tools
  负责人: [你的名字]
```

**每项推断结果 MUST 经用户确认。** 未确认的推断不得写入 .devops.yaml。

### Step 4: 生成 .devops.yaml

根据确认后的信息填充模板：

```yaml
service:
  name: {确认的服务名}
  domain: {用户选择的域}
  owner: {用户指定的负责人}

gitops:
  repo: {platform-inventory.yaml 的 gitlab.url}/{gitlab.gitops_repo}
  path: services/{domain}/{service}

runtime:
  language: {确认的语言}
  port: {确认的端口}
  health_check: {确认的健康检查路径}
  metrics: /metrics
  slow_start: {确认的慢启动标识}
  migration_command: {确认的 migration 命令}   # 仅当推断到或用户设置时才包含此字段

dependencies: []   # 或包含用户确认的依赖
```

**字段自动填充规则：**
- `gitops.repo` → 从 `platform-inventory.yaml` 的 `gitlab.url` + `gitlab.gitops_repo` 拼接
- `gitops.path` → `services/{domain}/{service}` 固定公式
- `runtime.metrics` → 默认 `/metrics`
- `runtime.migration_command` → 仅当 Step 2 推断到 migration 配置或用户主动设置后才写入；未推断到且用户未设置则不包含此字段

### Step 5: 资源规格选择

```
请选择资源规格等级：
  S - 轻量级（CPU 100m-500m, 内存 128Mi-512Mi）
  M - 标准（CPU 250m-1000m, 内存 256Mi-1Gi）   ← 推荐
  L - 高负载（CPU 500m-2000m, 内存 512Mi-2Gi）

如需超出 L 的配置，需要走额外审批流程。
```

用户选择后记录等级，用于生成 overlay。

### Step 6: 冲突检测

通过 MCP clone 配置仓库后检查：

```
1. services/{domain}/{service}/ 是否已存在 → 存在则提示冲突
2. 如有 owner 依赖：resources/{domain}/{type}/{name}/ 是否已存在 → 存在则提示冲突
```

冲突时的行为：
- 服务目录冲突 → 提示"该服务已存在于配置仓库，是否要使用其他服务名？"
- 资源冲突 → 提示"该资源已存在，是否改为 consumer 引用？"

### Step 7: 生成配置仓库文件

按 platform-spec.md 模板生成。**Ingress 文件根据目标集群的 ingress.class 动态选择格式**（见 platform-spec.md 第 6.3 节）。

**服务文件（必创建）：**
```
services/{domain}/{service}/
├── base/
│   ├── deployment.yaml      ← 第 6.1 节模板，含 securityContext
│   ├── service.yaml          ← 第 6.2 节模板
│   ├── ingress.yaml          ← 第 6.3 节 Nginx 模板（当 ingress.class=nginx）
│   │   或 ingressroute.yaml  ← 第 6.3 节 Traefik 模板（当 ingress.class=traefik）
│   │   及 middleware.yaml    ← 第 6.3 节 Traefik StripPrefix 中间件（如需路径前缀）
│   └── kustomization.yaml    ← 第 6.4 节模板
└── overlays/
    ├── int/kustomization.yaml     ← 用户选择的资源等级
    ├── test/kustomization.yaml
    ├── staging/kustomization.yaml
    └── prod/kustomization.yaml
```

**资源文件（仅当有 owner/producer 依赖时创建）：**
```
resources/{domain}/{type}/{name}/
├── base/
│   └── instance.yaml 或 topic.yaml    ← 第 6.5/6.6/6.7 节模板
└── overlays/
    ├── int/kustomization.yaml
    ├── test/kustomization.yaml
    ├── staging/kustomization.yaml
    └── prod/kustomization.yaml
```

**overlay 差异规则：**
- int: 用户选择的资源等级，replicas=1
- test: 同 int
- staging: 同 int
- prod: 资源等级上调一档（S→M, M→L, L→L），replicas=3，添加 ingress host

### Step 8: 展示变更方案

```
将创建以下文件：

配置仓库（通过 MR）:
  services/trade/order-service/base/deployment.yaml
  services/trade/order-service/base/service.yaml
  services/trade/order-service/base/ingress.yaml
  services/trade/order-service/base/kustomization.yaml
  services/trade/order-service/overlays/int/kustomization.yaml
  services/trade/order-service/overlays/test/kustomization.yaml
  services/trade/order-service/overlays/staging/kustomization.yaml
  services/trade/order-service/overlays/prod/kustomization.yaml
  resources/trade/mysql/order-service-db/base/instance.yaml
  resources/trade/mysql/order-service-db/overlays/int/kustomization.yaml
  ...（共 N 个文件）

代码仓库（本地）:
  .devops.yaml

确认创建？
```

### Step 9: 提交变更

用户确认后：

1. **代码仓库**：在当前目录创建 `.devops.yaml` 文件
2. **配置仓库**（通过 MCP）：
   - 创建分支：`init/{service}`
   - 创建所有文件
   - commit message: `feat: init {service} devops config`
   - push 并创建 MR
   - MR 描述模板：
     ```
     ## 服务初始化: {service}

     **发起人:** {owner}
     **域:** {domain}
     **操作:** init-service

     ### 创建的文件
     - services/{domain}/{service}/ (base + 4 环境 overlay)
     - resources/{domain}/{type}/{name}/ (如有 owner 依赖)

     ### 服务配置
     - 语言: {language}
     - 端口: {port}
     - 资源等级: {size}
     - 依赖: {dependencies 列表}

     ---
     _由 /devops skill 自动生成_
     ```

### Step 10: CI 配置检查

提交完成后，检查代码仓库的 CI 配置（详见 CI 检查规范）：

1. `.gitlab-ci.yml` 是否存在
2. 是否包含部署步骤（更新配置仓库镜像 tag）
3. 镜像 tag 是否使用 git sha
4. 是否推送到正确的 Harbor 项目
5. **（离线集群）** Dockerfile 是否从 registry 拉取基础镜像
6. **（离线集群）** 是否使用 deps 镜像模式（Kaniko 构建零网络依赖）

**离线集群额外检查（当 cluster.network=offline 时）：**
- Dockerfile 中 FROM 指令 MUST 使用 `{registry.url}/library/` 前缀
- 如有 `apt-get`/`pip install`/`npm ci` 等网络操作，MUST 在预构建的 deps 基础镜像中完成
- Kaniko 构建参数 MUST 包含 `--skip-tls-verify`（当 registry.insecure=true）

**检查结果处理：**
- 全部通过 → 仅展示"CI 配置检查通过"
- 有缺失 → 逐项展示问题，询问"是否需要帮你生成/优化 CI 配置？"
- 用户请求帮助 → 按语言生成基础 CI 配置（见 CI 配置模板）

### Step 11: 展示结果与下一步

```
✓ 服务初始化完成

已创建:
  - .devops.yaml（代码仓库）
  - MR: {MR 链接}（配置仓库，共 N 个文件）

下一步:
  1. Review 并合并配置仓库 MR
  2. 将 .devops.yaml commit 到代码仓库
  3. push 代码后，CI 将自动构建镜像并部署到 int 环境
  4. 如需添加更多依赖，运行 /devops 添加依赖
```

---

## MR 创建规范

| 项目 | 规范 |
|------|------|
| 分支命名 | `init/{service}` |
| commit message | `feat: init {service} devops config` |
| MR title | `feat: init {service} devops config` |
| MR reviewer | 域对应的 owner（从 CODEOWNERS 自动匹配） |
| 超额资源 | MR 额外添加平台团队 reviewer |
