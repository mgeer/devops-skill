# DevOps 平台规范（Platform Spec）

本文档是 AI Skill 执行操作时的**唯一规范来源**。所有路径、命名、模板、边界规则以本文档为准。

---

## 1. 配置仓库目录结构

```
gitops-repo/
├── platform-inventory.yaml          # 平台知识源（平台团队维护）
├── CODEOWNERS                       # 审批权限
│
├── infrastructure/                  # 第 1 层：平台基础设施（Helm）
│   ├── operators/
│   │   ├── strimzi-kafka/
│   │   ├── mysql-operator/
│   │   └── redis-operator/
│   ├── monitoring/
│   │   ├── prometheus/
│   │   ├── loki/
│   │   ├── tempo/
│   │   └── grafana/
│   └── ingress/
│       └── nginx/
│
├── resources/                       # 第 2 层：逻辑资源（Kustomize overlay）
│   └── {domain}/
│       ├── kafka/{topic-name}/
│       │   ├── base/topic.yaml
│       │   └── overlays/{env}/kustomization.yaml
│       ├── mysql/{instance-name}/
│       │   ├── base/instance.yaml
│       │   └── overlays/{env}/kustomization.yaml
│       └── redis/{instance-name}/
│           ├── base/instance.yaml
│           └── overlays/{env}/kustomization.yaml
│
├── services/                        # 第 3 层：业务服务（Kustomize overlay）
│   └── {domain}/
│       └── {service-name}/
│           ├── base/
│           │   ├── deployment.yaml
│           │   ├── service.yaml
│           │   ├── ingress.yaml              # Nginx，或：
│           │   │   (ingressroute.yaml         # Traefik IngressRoute
│           │   │    middleware.yaml)           # Traefik Middleware（有路径前缀时）
│           │   └── kustomization.yaml
│           └── overlays/{env}/
│               └── kustomization.yaml
│
└── argocd/
    └── appset.yaml                  # ApplicationSet（AI 不操作此目录）
```

**关键规则：**
- AI **永远不操作** `infrastructure/` 和 `argocd/` 目录
- AI 操作范围仅限 `services/` 和 `resources/`
- 每个 overlay 环境（int/test/staging/prod）独立一个 `kustomization.yaml`

---

## 2. 路径公式

AI 生成路径时 MUST 使用以下公式，不做任何变通：

| 资源类型 | 路径模板 |
|---------|---------|
| 服务 base | `services/{domain}/{service}/base/` |
| 服务 overlay | `services/{domain}/{service}/overlays/{env}/kustomization.yaml` |
| MySQL 实例 base | `resources/{domain}/mysql/{instance-name}/base/instance.yaml` |
| MySQL 实例 overlay | `resources/{domain}/mysql/{instance-name}/overlays/{env}/kustomization.yaml` |
| Redis 实例 base | `resources/{domain}/redis/{instance-name}/base/instance.yaml` |
| Redis 实例 overlay | `resources/{domain}/redis/{instance-name}/overlays/{env}/kustomization.yaml` |
| Kafka topic base | `resources/{domain}/kafka/{topic-name}/base/topic.yaml` |
| Kafka topic overlay | `resources/{domain}/kafka/{topic-name}/overlays/{env}/kustomization.yaml` |

**变量来源：**
- `{domain}` → `.devops.yaml` 的 `service.domain`
- `{service}` → `.devops.yaml` 的 `service.name`
- `{instance-name}` → 命名规范生成（见第 3 节）
- `{topic-name}` → 命名规范生成（见第 3 节）
- `{env}` → `int` | `test` | `staging` | `prod`

---

## 3. 命名规范

AI 生成资源名时 MUST 使用以下规则：

| 资源 | 命名规则 | 示例 | 校验正则 |
|------|---------|------|---------|
| 服务名 | 小写字母+数字+连字符，2-40 字符 | `order-service` | `^[a-z][a-z0-9-]{1,39}$` |
| Namespace | `{env}-{domain}` | `int-trade` | `^(int\|test\|staging\|prod)-[a-z][a-z0-9-]+$` |
| MySQL 实例 | `{service}-db` | `order-service-db` | — |
| Redis 实例 | `{service}-cache` | `order-service-cache` | — |
| Kafka topic | `{domain}.{service}.{event}` | `trade.order-service.created` | — |
| Docker 镜像 | `{registry}/{domain}/{service}:{git-sha-short}` | `harbor.company.com/trade/order-service:a1b2c3d` | — |

**标签规范（所有资源 MUST 包含）：**

| 标签 | 值 | 说明 |
|------|---|------|
| `app` | `{service}` | 服务名 |
| `domain` | `{domain}` | 业务域 |
| `managed-by` | `devops-skill` | 固定值 |
| `owner` | `{service}` | 资源所有者（仅 resources 层） |

---

## 4. 环境管理

### 4.1 集群与环境映射

| 集群 | 环境 | 审批要求 |
|------|------|---------|
| non-prod | int | 无（CI 直推） |
| non-prod | test | 团队内 review |
| non-prod | staging | Tech Lead 审批 |
| prod | prod | Tech Lead + SRE 审批 |

### 4.2 环境推进策略

| 环境 | 触发方式 | 配置仓库操作 |
|------|---------|-------------|
| int | CI 自动 | 直推 main 分支（仅 newTag） |
| test | 手动/AI | 创建 MR |
| staging | 手动/AI | 创建 MR |
| prod | 手动/AI | 创建 MR |

### 4.3 ArgoCD 同步策略

| 环境 | Auto-Sync | Self-Heal | Prune |
|------|-----------|-----------|-------|
| int | 开启 | 开启 | 开启 |
| test | 关闭 | 开启 | 关闭 |
| staging | 关闭 | 开启 | 关闭 |
| prod | 关闭 | 开启 | 关闭 |

---

## 5. Base/Overlay 边界规则

Base 放"结构"（环境无关的完整定义），overlay 只放"差异值"。

| 类别 | 放在 base | 放在 overlay |
|------|----------|-------------|
| Deployment 结构 | container/ports/probes/securityContext | — |
| 副本数 | — | replicas（JSON patch） |
| 资源限制 | — | resources.requests/limits（JSON patch） |
| 镜像 tag | — | images.newTag |
| 环境变量-固定 | `SERVICE_NAME` 等 | — |
| 环境变量-环境相关 | — | `DB_HOST`/`KAFKA_BOOTSTRAP` 等 |
| Service | 完整定义 | — |
| Ingress host | — | host 域名（JSON patch） |
| Secret 引用 | — | envFrom secretRef（JSON patch） |

**原则：** overlay 漏改时 `kustomize build` 报错（大声失败），完整文件漏改时静默使用旧值。遗漏比语法错误更危险。

---

## 6. Base 标准模板

### 6.1 Deployment 模板

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {service}
  labels:
    app: {service}
    domain: {domain}
    managed-by: devops-skill
spec:
  selector:
    matchLabels:
      app: {service}
  template:
    metadata:
      labels:
        app: {service}
        domain: {domain}
    spec:
      securityContext:
        runAsNonRoot: true
      containers:
        - name: {service}
          image: harbor.company.com/{domain}/{service}
          ports:
            - containerPort: {port}
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
          livenessProbe:
            httpGet:
              path: {health_check}
              port: {port}
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: {health_check}
              port: {port}
            initialDelaySeconds: 5
            periodSeconds: 5
          env:
            - name: SERVICE_NAME
              value: {service}
```

**startupProbe 条件逻辑：** 当 `.devops.yaml` 中 `runtime.slow_start: true` 时（通常 Java 服务），额外添加：

```yaml
          startupProbe:
            httpGet:
              path: {health_check}
              port: {port}
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 30
```

**DB Migration init container 条件逻辑：** 当 `.devops.yaml` 中 `runtime.migration_command` 有值且 dependencies 中有 `mysql role=owner` 时，在 `spec.template.spec` 中添加 init container（模板见 §12.2）。

**securityContext 规则（不可省略）：**
- Pod 级：`runAsNonRoot: true`
- Container 级：`readOnlyRootFilesystem: true` + `allowPrivilegeEscalation: false`

### 6.2 Service 模板

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {service}
  labels:
    app: {service}
    domain: {domain}
    managed-by: devops-skill
spec:
  selector:
    app: {service}
  ports:
    - port: 80
      targetPort: {port}
      protocol: TCP
```

### 6.3 Ingress 模板

根据 `platform-config.yaml` 中目标集群的 `ingress.class` 选择模板。

#### 6.3.1 Nginx Ingress 模板（当 ingress.class=nginx）

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {service}
  labels:
    app: {service}
    domain: {domain}
    managed-by: devops-skill
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {service}
                port:
                  number: 80
```

host 不在 base 中设置，由 overlay 通过 JSON patch 添加。

#### 6.3.2 Traefik IngressRoute 模板（当 ingress.class=traefik）

当使用路径前缀（如 `/{prefix}`）时，需要同时生成 **IngressRoute** 和 **Middleware**：

**ingressroute.yaml:**

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: {service}
  labels:
    app: {service}
    domain: {domain}
    managed-by: devops-skill
spec:
  entryPoints:                          # ← 从 ingress.entrypoints 中取非 TLS 的入口点
    - web                               #    如需 HTTPS 也加 websecure
  routes:
    - match: PathPrefix(`/{prefix}`)    # ← 路径前缀由用户指定，无前缀时用 Host 匹配
      kind: Rule
      middlewares:
        - name: {service}-strip-prefix  # ← 仅在有路径前缀时需要
      services:
        - name: {service}
          port: 80
```

> 无路径前缀时，match 规则改为 `Host(\`{host}\`)`，不需要 middleware。

**middleware.yaml（仅在有路径前缀时生成）：**

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {service}-strip-prefix
  labels:
    app: {service}
    domain: {domain}
    managed-by: devops-skill
spec:
  stripPrefix:
    prefixes:
      - /{prefix}
```

**多组件服务（如 backend + frontend）** 在同一个 IngressRoute 中定义多条 routes，按路径前缀长度降序排列（最长匹配优先）。

#### 6.3.3 Ingress 模板选择规则

| 条件 | 生成文件 | kustomization 引用 |
|------|---------|-------------------|
| ingress.class=nginx | ingress.yaml | `- ingress.yaml` |
| ingress.class=traefik，无路径前缀 | ingressroute.yaml | `- ingressroute.yaml` |
| ingress.class=traefik，有路径前缀 | ingressroute.yaml + middleware.yaml | `- ingressroute.yaml`<br>`- middleware.yaml` |

### 6.4 Kustomization 模板（base）

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml          # ← 或 ingressroute.yaml + middleware.yaml（Traefik）
```

### 6.5 MySQL 实例模板（base）

```yaml
apiVersion: mysql.oracle.com/v2
kind: InnoDBCluster
metadata:
  name: {instance-name}
  labels:
    app: {instance-name}
    domain: {domain}
    owner: {service}
    managed-by: devops-skill
spec:
  instances: 1
  router:
    instances: 1
  tlsUseSelfSigned: true
```

### 6.6 Redis 实例模板（base）

```yaml
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: {instance-name}
  labels:
    app: {instance-name}
    domain: {domain}
    owner: {service}
    managed-by: devops-skill
spec:
  kubernetesConfig:
    resources:
      requests:
        cpu: 100m
        memory: 64Mi
      limits:
        cpu: 500m
        memory: 256Mi
```

### 6.7 Kafka Topic 模板（base）

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: {topic-name}
  labels:
    strimzi.io/cluster: kafka-cluster
    app: {topic-name}
    domain: {domain}
    owner: {service}
    managed-by: devops-skill
spec:
  partitions: 1
  replicas: 1
  config:
    retention.ms: "604800000"
```

---

## 7. Kustomize Patch 标准模板

AI 生成 overlay 时 MUST 使用以下标准 patch 模板。常见操作用固定模板，不动态生成。

### 7.1 Overlay Kustomization 结构

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: {env}-{domain}
images:
  - name: harbor.company.com/{domain}/{service}
    newTag: "latest"
patches:
  - target:
      kind: Deployment
      name: {service}
    patch: |
      # patches 内容见下方模板
```

### 7.2 Replicas Patch

```yaml
      - op: replace
        path: /spec/replicas
        value: {replicas}
```

### 7.3 Resources Patch（S/M/L 等级）

```yaml
      - op: add
        path: /spec/template/spec/containers/0/resources
        value:
          requests: { cpu: {cpu_req}, memory: {mem_req} }
          limits: { cpu: {cpu_lim}, memory: {mem_lim} }
```

### 7.4 环境变量 Patch（追加）

```yaml
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: {ENV_NAME}
          value: {env_value}
```

### 7.5 Secret 引用 Patch（envFrom）

```yaml
      - op: add
        path: /spec/template/spec/containers/0/envFrom
        value:
          - secretRef:
              name: {instance-name}-secret
```

### 7.6 Ingress Host Patch

**Nginx Ingress（ingress.class=nginx）：**

```yaml
  - target:
      kind: Ingress
      name: {service}
    patch: |
      - op: add
        path: /spec/rules/0/host
        value: {service}.company.com
```

**Traefik IngressRoute（ingress.class=traefik）：**

Traefik 的 host 在 IngressRoute 的 match 规则中设置。overlay 通过 JSON patch 修改 match 字段添加 Host 条件：

```yaml
  - target:
      kind: IngressRoute
      name: {service}
    patch: |
      - op: replace
        path: /spec/routes/0/match
        value: "Host(`{host}`) && PathPrefix(`/{prefix}`)"
```

> 如有多条 routes，每条都需要添加 Host 条件。

### 7.7 MySQL Prod Patch 示例

```yaml
  - target:
      kind: InnoDBCluster
      name: {instance-name}
    patch: |
      - op: replace
        path: /spec/instances
        value: 3
      - op: replace
        path: /spec/router/instances
        value: 2
```

### 7.8 Kafka Topic Prod Patch 示例

```yaml
  - target:
      kind: KafkaTopic
      name: {topic-name}
    patch: |
      - op: replace
        path: /spec/partitions
        value: 6
      - op: replace
        path: /spec/replicas
        value: 3
```

### 7.9 Resource Overlay

结构与 services overlay 相同（§7.1），int 通常无需 patch（用 base 默认值），prod 添加 patches（见 §7.7/7.8）。

---

## 8. 资源规格等级

| 等级 | CPU requests | CPU limits | Memory requests | Memory limits | 适用场景 |
|------|-------------|------------|-----------------|---------------|---------|
| S | 100m | 500m | 128Mi | 512Mi | 轻量级服务、sidecar |
| M | 250m | 1000m | 256Mi | 1Gi | 标准业务服务（默认推荐） |
| L | 500m | 2000m | 512Mi | 2Gi | 高负载服务 |

**规则：**
- init-service 时引导用户选择等级
- 后续调整可指定具体值
- 超出 L 等级 → MR 自动添加平台团队 reviewer + 描述标注"资源超额"

---

## 9. Secret 命名约定

AI 只写 secretRef 引用，**绝不接触密码值**。

| 中间件类型 | Secret 名称 | 包含的 key |
|-----------|------------|-----------|
| MySQL | `{instance-name}-secret` | `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` |
| Redis | `{instance-name}-secret` | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |
| Kafka | 无需 Secret | 通过 `KAFKA_BOOTSTRAP` 环境变量连接 |

**Secret 由 Operator 在集群内自动创建，不经过 Git。**

**KAFKA_BOOTSTRAP 值来源：** `platform-inventory.yaml` 的 `middleware.kafka.bootstrap` 字段。

---

## 10. 资源所有权模型

| 资源类型 | 所有者角色 | 共享方式 |
|---------|-----------|---------|
| MySQL 实例 | `owner`（创建者独占） | 一般不共享 |
| Redis 实例 | `owner`（创建者独占） | 一般不共享 |
| Kafka topic | `producer`（创建者拥有） | consumer 通过 .devops.yaml 声明引用 |

**跨域依赖：**
- .devops.yaml 的 dependencies 条目有可选 `domain` 字段
- 同域引用时省略（默认为 `service.domain`）
- 跨域引用时 MUST 填写目标域名
- AI 遇到跨域依赖时 MUST 额外提示确认

**依赖检查策略："尽力检查 + 不确定就问"**
- MySQL/Redis：搜索配置仓库 overlay 中的 `{instance-name}-secret` secretRef 引用，反查消费方
- Kafka topic：无法从配置仓库确认消费方 → MUST 询问用户
- 不维护额外的依赖追踪文件

---

## 11. GitOps 工作流

### 11.1 CI 直推（仅 int 环境镜像 tag）

```
CI pipeline → clone gitops-repo → 修改 overlays/int/kustomization.yaml 的 newTag
→ git commit -m "ci: update {service} image to {tag}" → git push（含 rebase 重试）
→ ArgoCD 自动同步
```

**直推范围限制：** 仅允许修改 `overlays/int/kustomization.yaml` 的 `images[].newTag` 字段。任何其他变更 MUST 走 MR。

### 11.2 MR 推进（test/staging/prod）

```
CI 或 AI → clone gitops-repo → 创建分支 → 修改目标 overlay → push 分支
→ 创建 MR（描述含发起人、意图、影响范围）→ 审批 → merge → ArgoCD 同步
```

### 11.3 凭证

| 凭证 | 用途 | 存储位置 |
|------|------|---------|
| GitLab Deploy Token | CI 推送配置仓库 | GitLab CI 变量（protected） |
| Harbor Robot Account | CI 推送镜像 | GitLab CI 变量（protected） |
| ArgoCD Repo Credential | ArgoCD 拉取配置仓库 | K8s Secret |

---

## 12. DB Migration 执行规范

### 12.1 策略

- **执行方式：** 应用自身镜像作为 initContainer 运行 migration 命令
- **工具选择：** 由项目自行决定（Python 用 Alembic、Java 用 Flyway、Go 用 golang-migrate 等），平台不绑定特定工具
- **策略：** Forward-only，不支持 DOWN migration
- **命令：** 由 `.devops.yaml` 的 `runtime.migration_command` 指定

### 12.2 Init Container 模板

当 `.devops.yaml` 包含 `runtime.migration_command` 且 dependencies 中有 `mysql role=owner` 时，AI 生成 deployment.yaml SHALL 在 base 中包含以下 init container：

```yaml
      initContainers:
        - name: db-migrate
          image: {与主容器相同的镜像}
          command: ["sh", "-c", "{migration_command}"]
          envFrom:
            - secretRef:
                name: {instance-name}-secret
```

**变量说明：**
- **`image`**：与主容器 `spec.containers[0].image` 完全一致（同镜像、同 tag），确保 migration 代码版本与应用代码版本一致
- **`{migration_command}`**：从 `.devops.yaml` 的 `runtime.migration_command` 读取
- **`{instance-name}`**：从 dependencies 中 `type=mysql, role=owner` 的 `name` 字段获取
- **`envFrom`**：复用主容器的 Secret 引用，注入 MYSQL_HOST / MYSQL_PORT / MYSQL_USER / MYSQL_PASSWORD / MYSQL_DATABASE

### 12.3 条件逻辑

| 条件 | 行为 |
|------|------|
| 无 `runtime.migration_command` | 不生成 init container |
| 有 `migration_command` + 有 mysql owner | 生成 init container |
| 有 `migration_command` + 无 mysql owner | 警告"migration_command 已设置但无 MySQL owner 依赖" |

### 12.4 Dockerfile 约束

当 `.devops.yaml` 包含 `runtime.migration_command` 时，应用的 Dockerfile MUST 包含 migration 工具和 migration 文件。AI 在 ci-config-check 时应验证这一点。

常见语言示例：

| 语言 | migration 工具 | Dockerfile 要求 |
|------|---------------|-----------------|
| python | Alembic | `pip install alembic` + `COPY alembic/ /app/alembic/` + `COPY alembic.ini /app/` |
| java | Flyway | migration SQL 打进 jar 包（构建时自动包含） |
| go | golang-migrate | 编译时嵌入或 `COPY migrations/ /app/migrations/` |

---

## 13. 重命名操作标准流程

服务或资源重命名**不支持原地修改**。MUST 按以下三步执行：

### Step 1: 创建新资源
- 使用新名称按标准流程创建完整的 base + overlays
- 新旧共存，不影响现有服务

### Step 2: 迁移
- 数据迁移（如 MySQL 数据同步）由开发者手动完成
- 消费方切换引用（更新 .devops.yaml 的 dependencies）
- 验证新资源工作正常

### Step 3: 删除旧资源
- 确认所有消费方已切换
- 走 decommission 流程删除旧资源

**为什么不原地改名：** 原地修改涉及路径变更、label 变更、ArgoCD Application 重建，中间状态多且不可控。三步法每一步都是标准操作，AI 执行可靠。

---

## 14. .devops.yaml Schema 速查

```yaml
service:
  name: string          # ^[a-z][a-z0-9-]{1,39}$
  domain: string        # MUST 在 platform-inventory.yaml 的 domains 中
  owner: string         # 负责人

gitops:
  repo: string          # 配置仓库地址（从 platform-inventory.yaml 获取）
  path: string          # services/{domain}/{service}

runtime:
  language: enum        # go | java | node | python
  port: integer         # 1-65535
  health_check: string  # 默认 /healthz
  metrics: string       # 默认 /metrics
  slow_start: boolean   # 默认 false，true 时生成 startupProbe
  migration_command: string  # 可选，DB migration 命令（如 "alembic upgrade head"），有值时注入 init container

dependencies:           # 可选，数组
  - name: string        # 资源名
    type: enum          # mysql | redis | kafka-topic
    role: enum          # owner | producer | consumer
    domain: string      # 可选，跨域引用时必填
```

**合法 type+role 组合：**

| type | owner | producer | consumer |
|------|-------|----------|----------|
| mysql | ✓ | ✗ | ✓ |
| redis | ✓ | ✗ | ✓ |
| kafka-topic | ✗ | ✓ | ✓ |
