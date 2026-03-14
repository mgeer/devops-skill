# Flow: decommission — 安全下线服务

## 触发条件
- 用户意图：下线、废弃、删除服务
- 前置条件：.devops.yaml 已存在

**核心原则：** 下线是高危操作，Skill 的角色是引导和检查，不自动删除。每一步都需要用户明确确认。

---

## 完整流程

### Step 1: 意图确认

下线是不可逆操作，首先需要二次确认：

```
你确定要下线 {service} 吗？

这将:
  - 删除配置仓库中 services/{domain}/{service}/ 的所有文件
  - 删除该服务拥有的资源（如确认安全）
  - ArgoCD 将从集群中移除对应的 Deployment/Service/Ingress

此操作不可逆。确认继续？
```

### Step 2: 读取服务信息

从 `.devops.yaml` 中提取：
- 服务名、域、负责人
- 拥有的资源列表（role=owner 或 role=producer 的 dependencies）
- consumer 引用列表（role=consumer）

### Step 3: 依赖影响分析

**原则："尽力检查 + 不确定就问"**

#### 3.1 分析拥有的资源

对每个 owner/producer 资源执行消费方检查：

**MySQL/Redis（可从配置仓库反查）：**
```bash
# 搜索所有服务的 overlay，查找引用此 Secret 的 secretRef
grep -r "{instance-name}-secret" services/*/overlays/
```

| 搜索结果 | 判定 | 行为 |
|---------|------|------|
| 找到其他服务引用 | 有消费方 | 列出消费方，阻止删除此资源 |
| 仅本服务引用或无引用 | 无消费方 | 可安全删除 |
| 不确定（搜索异常等） | 未知 | 询问用户 |

**Kafka topic（无法从配置仓库确认）：**
```
Kafka topic {topic-name} 的消费方无法从配置仓库确认。
是否有其他服务正在消费此 topic？

如果不确定，建议先保留 topic，仅下线服务。
```

#### 3.2 展示分析结果

```
依赖影响分析:

拥有的资源:
  ✓ order-service-db (mysql, owner) — 无其他消费方，可安全删除
  ✗ trade.order-service.created (kafka-topic, producer) — 有消费方:
      - notification-service (consumer)
      - analytics-service (consumer)

Consumer 引用（本服务消费的资源）:
  - user-events (kafka-topic, consumer) — 仅需移除本服务引用
```

### Step 4: 处理有消费方的资源

对于有消费方的资源，**阻止删除并给出建议**：

```
以下资源有其他服务依赖，无法随服务一起删除：
  - trade.order-service.created (consumer: notification-service, analytics-service)

处理建议：
  1. 转移所有权 — 将 topic 的 producer 角色转给其他服务
  2. 通知消费方 — 让消费方先移除依赖
  3. 保留资源 — 仅下线服务，保留 topic（成为孤儿资源）

请选择处理方式，或跳过此资源继续下线流程。
```

**跨域消费方通知：** 如果消费方来自其他域，额外提示：
```
注意: notification-service 属于 notify 域
请联系该域负责人协调处理。
```

### Step 5: 逐个确认删除

对可安全删除的资源逐个确认：

```
以下资源将被删除:

  1. order-service-db (mysql)
     路径: resources/trade/mysql/order-service-db/（base + 所有 overlay）
     确认删除？ [y/n]

  2. 服务配置
     路径: services/trade/order-service/（base + 所有 overlay）
     确认删除？ [y/n]
```

### Step 6: 创建 MR

确认后，通过 MCP 执行：

- 分支：`decommission/{service}`
- 删除确认的目录和文件
- commit message: `feat: decommission {service}`
- 创建 MR

**MR MUST 包含 Tech Lead 作为 reviewer**（下线是高危操作）。

MR 描述模板：
```
## 服务下线: {service}

**发起人:** {owner}
**域:** {domain}
**操作:** decommission

### 删除的内容
- services/{domain}/{service}/（base + 4 环境 overlay）
- resources/{domain}/mysql/{instance-name}/（如确认删除）
- ...

### 保留的资源
- trade.order-service.created (kafka-topic) — 有消费方，未删除

### 消费方引用
本服务作为 consumer 引用的资源不受影响，仅移除本服务的引用。

### ⚠️ 需要 Tech Lead 审批
服务下线为高危操作，请 Tech Lead review 后合并。

---
_由 /devops skill 自动生成_
```

### Step 7: 手动清理事项

MR 创建后，输出待开发者手动处理的清单：

```
✓ 配置仓库 MR 已创建: {MR 链接}

以下事项需要你手动处理:

  □ 删除代码仓库中的 .devops.yaml
  □ 清理 .gitlab-ci.yml 中的部署步骤（更新配置仓库相关的 CI 步骤）
  □ 如有定时任务、消息消费等后台进程，确保已停止

MR 合并后的影响:
  - dev 环境: ArgoCD 自动清理（auto-sync + prune 已开启）
  - test/staging/prod: 需手动触发 ArgoCD sync，或等待 self-heal
  - Operator 管理的中间件实例将随 CR 删除被回收
  - ⚠️ 数据不可恢复，请确保已完成数据备份
```

---

## 安全保障总结

| 保障项 | 实现方式 |
|--------|---------|
| 二次确认 | Step 1 整体确认 + Step 5 逐资源确认 |
| 消费方检查 | Step 3 尽力检查 + 不确定就问 |
| 跨域通知 | Step 4 识别跨域消费方并提示联系 |
| 审批 | MR MUST 含 Tech Lead reviewer |
| 数据保护 | Step 7 提醒数据备份 |
| 可追溯 | MR 描述记录完整操作信息 |
