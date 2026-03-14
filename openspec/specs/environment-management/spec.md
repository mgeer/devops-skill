## ADDED Requirements

### Requirement: 两集群四环境拓扑

平台 SHALL 使用两个 K8s 集群承载四个环境：

| 集群 | 环境 | 用途 |
|------|------|------|
| non-prod | dev, test, staging | 开发、测试、预发布 |
| prod | prod | 生产 |

同一集群内的不同环境通过 namespace 隔离。

#### Scenario: 查看环境与集群的对应关系

- **WHEN** AI 需要确定 staging 部署到哪个集群
- **THEN** SHALL 从 platform-inventory.yaml 的 clusters 字段确认 staging 属于 non-prod 集群

#### Scenario: dev 和 test 的隔离

- **WHEN** dev-trade 和 test-trade 两个 namespace 存在于同一集群
- **THEN** 两个 namespace 之间 SHALL 通过 NetworkPolicy 隔离，默认不允许互相访问

---

### Requirement: namespace 命名规则

namespace SHALL 按 `{env}-{domain}` 格式命名。每个域在每个环境有且只有一个 namespace。

#### Scenario: trade 域在所有环境的 namespace

- **WHEN** trade 域接入平台
- **THEN** SHALL 创建四个 namespace：`dev-trade`、`test-trade`、`staging-trade`、`prod-trade`

#### Scenario: namespace 命名校验

- **WHEN** AI 生成 namespace 名称
- **THEN** 名称 SHALL 匹配正则 `^(dev|test|staging|prod)-[a-z][a-z0-9-]+$`

---

### Requirement: Kustomize base 与 overlay 内容边界

services 和 resources SHALL 使用 Kustomize overlay 管理环境差异。base/ 放环境无关的结构定义，overlays/{env}/ 只放环境差异 patch。

**base/ 内容（SHALL 包含）：**
- Deployment 结构（container、ports、probes、securityContext）
- Service 完整定义
- Ingress 结构（不含 host）
- ServiceMonitor 完整定义
- 固定环境变量（如 SERVICE_NAME）
- Labels（app、domain、team、managed-by）
- Pod securityContext（runAsNonRoot: true）
- Container securityContext（readOnlyRootFilesystem: true、allowPrivilegeEscalation: false）

**overlay/ 内容（SHALL 包含）：**
- namespace 声明
- replicas
- resources.requests/limits
- images.newTag
- 环境相关环境变量（DB_HOST、KAFKA_BOOTSTRAP 等）
- Ingress host 域名

#### Scenario: 创建服务 base 的 deployment.yaml

- **WHEN** AI 为 order-service 创建 base/deployment.yaml
- **THEN** SHALL 包含 container 定义、ports、probes、securityContext（runAsNonRoot + readOnlyRootFilesystem + allowPrivilegeEscalation:false）、固定环境变量，不得包含 replicas、resources limits、环境相关环境变量

#### Scenario: 创建 prod overlay

- **WHEN** AI 为 order-service 创建 overlays/prod/kustomization.yaml
- **THEN** SHALL 包含 namespace（prod-trade）、replicas patch、resources limits patch、环境相关环境变量 patch、images.newTag

#### Scenario: base 中误包含环境相关配置

- **WHEN** base/deployment.yaml 中包含 `replicas: 1`
- **THEN** 这是一个规范违反——replicas 属于环境差异，SHALL 通过 overlay patch 设置

---

### Requirement: overlay kustomization.yaml 结构

每个 overlay 的 kustomization.yaml MUST 包含 `resources`（引用 base）和 `namespace` 字段。`patches` 和 `images` 根据需要添加。

```yaml
# 最小 overlay（无环境差异时）
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: {env}-{domain}

# 有环境差异时
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
      - op: replace
        path: /spec/replicas
        value: 3
```

#### Scenario: dev overlay 使用默认配置

- **WHEN** dev 环境不需要特殊配置（使用 base 默认值）
- **THEN** overlay SHALL 只包含 resources、namespace 和 images（用于 CI 更新 tag），无需 patches

#### Scenario: kustomize build 验证

- **WHEN** 对任意 overlay 目录执行 `kustomize build`
- **THEN** SHALL 成功输出完整的 K8s 资源 YAML，不得有错误

---

### Requirement: 环境推进策略

环境推进 SHALL 按 dev → test → staging → prod 顺序进行。每个环境的推进方式不同：

| 环境 | 触发方式 | 配置仓库操作 | 审批要求 |
|------|---------|-------------|---------|
| dev | 代码 push 触发 CI | CI 直推 main（仅镜像 tag） | 无 |
| test | 开发者通过 `/devops` 触发 | AI 创建 MR | 团队内 review |
| staging | 开发者通过 `/devops` 触发 | AI 创建 MR | Tech Lead 审批 |
| prod | 开发者通过 `/devops` 触发 | AI 创建 MR | Tech Lead + SRE 审批 |

#### Scenario: 代码 push 自动部署到 dev

- **WHEN** 开发者 push 代码到代码仓库
- **THEN** CI SHALL 构建镜像、推送 Harbor、直接更新配置仓库 dev overlay 的 newTag 并 push 到 main

#### Scenario: 推进到 staging

- **WHEN** 开发者说"部署到 staging"
- **THEN** AI SHALL 创建 MR，更新 staging overlay 的 newTag 为当前 dev/test 验证过的镜像 tag，MR reviewer MUST 包含 Tech Lead

#### Scenario: 跳过环境推进

- **WHEN** 开发者请求直接从 dev 部署到 prod（跳过 test 和 staging）
- **THEN** AI SHALL 警告"跳过了 test 和 staging 环境验证，确认继续？"并要求明确确认
