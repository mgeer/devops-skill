# Flow: remove-dependency — 移除已有依赖

## 触发条件
- 用户意图：移除依赖、删除依赖、不再使用某资源
- 前置条件：.devops.yaml 已存在

---

## 完整流程

### Step 1: 前置检查

1. 读取 `.devops.yaml`，确认服务已接入
2. 确认 `dependencies` 不为空
3. 通过 MCP clone 配置仓库

### Step 2: 确认要移除的依赖

列出当前 dependencies：

```
当前服务的依赖:
  1. order-service-db (mysql, owner)
  2. trade.order-service.created (kafka-topic, producer)
  3. user-events (kafka-topic, consumer, domain: user)

要移除哪个依赖？
```

### Step 3A: Consumer 移除

consumer 移除相对简单，不涉及资源本身的删除。

#### 3A.1 移除环境变量引用
从服务的**每个环境 overlay** 中移除对应的环境变量：
- MySQL/Redis consumer → 移除 envFrom secretRef 中对 `{instance-name}-secret` 的引用
- Kafka consumer → 如果 KAFKA_BOOTSTRAP 仅由此依赖使用，移除该环境变量

#### 3A.2 更新 .devops.yaml
从 dependencies 数组中删除对应条目。

### Step 3B: Owner/Producer 移除

owner/producer 移除涉及资源本身的删除，需要安全检查。

#### 3B.1 消费方检查（尽力检查 + 不确定就问）

**MySQL/Redis:**
在配置仓库中搜索所有 overlay 文件，查找 `{instance-name}-secret` 的 secretRef 引用：
```bash
# 搜索所有 overlay 中的 secretRef 引用
grep -r "{instance-name}-secret" services/*/overlays/
```
- 找到引用 → 列出消费方服务，**阻止删除**
- 未找到引用 → 继续（可能安全删除）
- 搜索结果不确定 → 询问用户

**Kafka topic:**
无法从配置仓库确认消费方（consumer 通过环境变量直接使用 bootstrap 地址，不引用 topic Secret）。
MUST 询问用户：
```
Kafka topic {topic-name} 的消费方无法从配置仓库确认。
是否有其他服务正在消费此 topic？
  - 是（请列出） → 阻止删除
  - 否 → 继续删除
  - 不确定 → 建议保留，先确认后再操作
```

#### 3B.2 有消费方 → 阻止

```
无法删除 {resource-name}，以下服务依赖此资源：
  - notification-service (consumer)
  - analytics-service (consumer)

请先让消费方移除依赖（/devops 移除依赖），或将资源所有权转移给其他服务。
```

#### 3B.3 无消费方 → 确认删除

```
{resource-name} 无其他消费方，将执行以下操作：
  - 删除资源目录: resources/{domain}/{type}/{name}/（base + 所有 overlay）
  - 移除服务 overlay 中的环境变量引用
  - 更新 .devops.yaml

确认删除？
```

### Step 4: 展示变更方案

```
将执行以下变更：

.devops.yaml（代码仓库）:
  - dependencies 移除: order-service-db (mysql, owner)

配置仓库（通过 MR）:
  - resources/trade/mysql/order-service-db/（整个目录删除）
  ~ services/trade/order-service/overlays/dev/kustomization.yaml  (- envFrom secretRef)
  ~ services/trade/order-service/overlays/test/kustomization.yaml (- envFrom secretRef)
  ~ services/trade/order-service/overlays/staging/kustomization.yaml (- envFrom secretRef)
  ~ services/trade/order-service/overlays/prod/kustomization.yaml (- envFrom secretRef)

确认？
```

### Step 5: 提交变更

1. 更新代码仓库 `.devops.yaml`
2. 配置仓库：
   - 分支：`remove-dep/{service}/{type}/{name}`
   - commit message: `feat: remove {type} {name} from {service}`
   - 创建 MR，描述：
     ```
     ## 移除依赖: {name} ({type})

     **发起人:** {owner}
     **服务:** {service} ({domain})
     **操作:** remove-dependency
     **原角色:** {role}

     ### 变更内容
     - 删除资源目录: resources/{domain}/{type}/{name}/ (仅 owner/producer)
     - 修改服务 overlay: 移除环境变量引用

     ---
     _由 /devops skill 自动生成_
     ```

### Step 6: 展示结果

```
✓ 依赖移除完成

已创建:
  - .devops.yaml 已更新（代码仓库）
  - MR: {MR 链接}（配置仓库）

注意:
  - MR 合并后，dev 环境将自动同步（资源被删除）
  - test/staging/prod 需手动触发 ArgoCD sync
  - 如果应用代码中仍引用此资源的连接信息，请同步清理代码
```
