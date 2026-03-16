# Flow: add-dependency — 为已接入服务添加中间件依赖

## 触发条件
- 用户意图：添加依赖、加 MySQL/Redis/Kafka
- 前置条件：.devops.yaml 已存在

---

## 完整流程

### Step 1: 前置检查

1. 读取 `.devops.yaml`，确认服务已接入（文件存在且格式正确）
2. 通过 MCP clone 配置仓库
3. 读取 `platform-inventory.yaml` 确认中间件可用性

```
中间件可用性检查:
  middleware.{type}.available == true → 可用
  middleware.{type}.available == false → 提示"该中间件尚未部署"，停止
  middleware.{type} 不存在 → 提示"平台不支持此中间件类型"，停止
```

### Step 2: 确认依赖类型

```
要添加什么依赖？
  1. MySQL 数据库
  2. Redis 缓存
  3. Kafka topic
```

### Step 3: 确认角色

根据依赖类型展示合法角色：

```
MySQL/Redis:
  owner  — 创建新实例（我拥有这个资源）
  consumer — 引用已有实例（别人创建的，我只是使用）

Kafka topic:
  producer — 创建新 topic（我拥有这个 topic）
  consumer — 消费已有 topic（别人创建的）
```

**非法组合（MUST 拒绝）：**
- mysql + producer → 提示"MySQL 使用 owner，不是 producer"
- redis + producer → 提示"Redis 使用 owner，不是 producer"
- kafka-topic + owner → 提示"Kafka topic 使用 producer，不是 owner"

### Step 4A: Owner/Producer 操作

#### 4A.1 生成资源名

按 platform-spec.md 命名规范：
- MySQL: `{service}-db`
- Redis: `{service}-cache`
- Kafka: `{domain}.{service}.{event}`（需要用户指定 event 名称）

```
Kafka 示例:
  AI: topic 的事件名是什么？（将生成: trade.order-service.{event}）
  用户: created
  AI: topic 名称: trade.order-service.created，确认？
```

#### 4A.2 冲突检查

检查配置仓库中 `resources/{domain}/{type}/{name}/` 是否已存在。
- 存在 → 提示"该资源已存在，是否改为 consumer 引用？"
- 不存在 → 继续

#### 4A.3 创建资源目录

按 platform-spec.md 模板创建：

```
resources/{domain}/{type}/{name}/
├── base/
│   └── instance.yaml 或 topic.yaml
└── overlays/
    ├── int/kustomization.yaml
    ├── test/kustomization.yaml
    ├── staging/kustomization.yaml
    └── prod/kustomization.yaml
```

**overlay 差异规则：**
- int: 使用 base 默认值
- prod: MySQL 3 instances + 2 routers, Kafka 6 partitions + 3 replicas

#### 4A.4 环境变量注入

在服务的**每个环境 overlay** 中添加环境变量引用：

**MySQL/Redis（envFrom secretRef）：**
```yaml
patches:
  - target:
      kind: Deployment
      name: {service}
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/envFrom
        value:
          - secretRef:
              name: {instance-name}-secret
```

注意：如果已有 envFrom，用 `path: /spec/template/spec/containers/0/envFrom/-` 追加。

**Kafka（环境变量）：**
```yaml
patches:
  - target:
      kind: Deployment
      name: {service}
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: KAFKA_BOOTSTRAP
          value: {platform-inventory.yaml 的 middleware.kafka.bootstrap}
```

KAFKA_BOOTSTRAP 值对所有环境相同（集群内服务发现地址）。如果已存在 KAFKA_BOOTSTRAP 则跳过。

### Step 4B: Consumer 操作

#### 4B.1 确认资源信息

```
AI: 请提供要引用的资源信息：
  资源名: [输入]
  所属域: [如果与当前服务同域可省略，跨域必填]
```

#### 4B.2 资源存在性验证

在配置仓库中检查 `resources/{target_domain}/{type}/{name}/base/` 是否存在。
- 不存在 → 提示"该资源在配置仓库中不存在。请确认资源名和域是否正确，或者联系资源 owner 先创建。"
- 存在 → 继续

#### 4B.3 跨域依赖检查

如果 `target_domain != service.domain`：
```
注意：这是一个跨域依赖。
  当前服务域: {service.domain}
  目标资源域: {target_domain}

跨域依赖可能需要:
  1. NetworkPolicy 放通（Change 5 实现）
  2. 两个团队之间的沟通协调

确认继续？
```

#### 4B.4 环境变量注入

与 4A.4 相同的注入逻辑。

对于 MySQL/Redis consumer，secretRef 中的 Secret 名称使用目标资源的 `{instance-name}-secret`。
Secret 需要与 consumer 在同一个 namespace 中存在。如果是跨域引用，AI MUST 提示：
```
注意：{instance-name}-secret 需要在 {env}-{consumer-domain} namespace 中存在。
请确认平台团队已配置好跨 namespace Secret 同步。
```

### Step 5: 更新 .devops.yaml

在 dependencies 数组中新增条目：

```yaml
dependencies:
  - name: {resource-name}
    type: {mysql|redis|kafka-topic}
    role: {owner|producer|consumer}
    domain: {target-domain}   # 仅跨域时填写
```

**去重检查：** 如果相同 name+type+role 的条目已存在，提示"该依赖已声明"，跳过。

### Step 6: 展示变更方案

```
将执行以下变更：

.devops.yaml（代码仓库）:
  + dependencies 新增: order-service-db (mysql, owner)

配置仓库（通过 MR）:
  + resources/trade/mysql/order-service-db/base/instance.yaml
  + resources/trade/mysql/order-service-db/overlays/int/kustomization.yaml
  + resources/trade/mysql/order-service-db/overlays/test/kustomization.yaml
  + resources/trade/mysql/order-service-db/overlays/staging/kustomization.yaml
  + resources/trade/mysql/order-service-db/overlays/prod/kustomization.yaml
  ~ services/trade/order-service/overlays/int/kustomization.yaml  (+ envFrom secretRef)
  ~ services/trade/order-service/overlays/test/kustomization.yaml (+ envFrom secretRef)
  ~ services/trade/order-service/overlays/staging/kustomization.yaml (+ envFrom secretRef)
  ~ services/trade/order-service/overlays/prod/kustomization.yaml (+ envFrom secretRef)

确认？
```

### Step 7: 提交变更

1. 更新代码仓库 `.devops.yaml`
2. 配置仓库：
   - 分支：`add-dep/{service}/{type}/{name}`
   - commit message: `feat: add {type} {name} for {service}`
   - 创建 MR，描述：
     ```
     ## 添加依赖: {name} ({type})

     **发起人:** {owner}
     **服务:** {service} ({domain})
     **操作:** add-dependency
     **角色:** {role}

     ### 变更内容
     - 新增资源目录: resources/{domain}/{type}/{name}/ (仅 owner/producer)
     - 修改服务 overlay: 添加环境变量注入

     ---
     _由 /devops skill 自动生成_
     ```

### Step 8: 展示结果

```
✓ 依赖添加完成

已创建:
  - .devops.yaml 已更新（代码仓库）
  - MR: {MR 链接}（配置仓库）

下一步:
  1. Review 并合并配置仓库 MR
  2. commit .devops.yaml 到代码仓库
  3. MR 合并后，ArgoCD 将同步资源到集群
  4. Operator 将自动创建 {instance-name}-secret（MySQL/Redis）
```
