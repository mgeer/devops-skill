## ADDED Requirements

### Requirement: 资源规格等级定义

平台 SHALL 预定义三个资源规格等级（S/M/L），用于 init-service 时引导用户选择服务的 CPU/内存配置。

| 等级 | CPU requests | CPU limits | Memory requests | Memory limits | 适用场景 |
|------|-------------|------------|-----------------|---------------|---------|
| S | 100m | 500m | 128Mi | 512Mi | 轻量级服务、sidecar |
| M | 250m | 1000m | 256Mi | 1Gi | 标准业务服务 |
| L | 500m | 2000m | 512Mi | 2Gi | 高负载服务 |

#### Scenario: 展示资源规格选择

- **WHEN** AI 在 init-service 流程中引导用户选择资源规格
- **THEN** AI SHALL 展示 S/M/L 三个等级的配置和适用场景，默认推荐 M（标准）

#### Scenario: 用户选择 S 等级

- **WHEN** 用户选择 S 等级资源规格
- **THEN** AI SHALL 在各环境 overlay 的 resources patch 中使用 S 等级的 CPU/内存配置

---

### Requirement: 资源规格写入 overlay

资源规格 SHALL 作为 Kustomize overlay patch 写入各环境的 kustomization.yaml，不同环境可使用不同规格。

#### Scenario: init-service 时设置默认规格

- **WHEN** 用户选择 M 等级
- **THEN** AI SHALL 在所有环境 overlay 中设置相同的资源规格：
  ```yaml
  patches:
    - target:
        kind: Deployment
        name: order-service
      patch: |
        - op: add
          path: /spec/template/spec/containers/0/resources
          value:
            requests: { cpu: 250m, memory: 256Mi }
            limits: { cpu: 1000m, memory: 1Gi }
  ```

#### Scenario: 后续调整资源规格

- **WHEN** 用户通过 `/devops` 请求调整资源规格（如"把 prod 的 CPU 改成 2000m"）
- **THEN** AI SHALL 直接修改对应环境 overlay 的 resources patch，不限制于 S/M/L 等级

---

### Requirement: 超额审批机制

当用户请求的资源配置超出 L 等级时，AI SHALL 在 MR 中添加平台团队审批。

#### Scenario: 初始化时选择超额配置

- **WHEN** 用户在 init-service 时选择"我需要 4 核 CPU、8Gi 内存"
- **THEN** AI SHALL 提示"该配置超出标准等级 L（最高 2000m CPU, 2Gi 内存），需要平台团队审批"，创建 MR 时自动添加平台团队作为 reviewer

#### Scenario: 后续调整超出标准

- **WHEN** 用户后续请求调整某环境资源超出 L 等级
- **THEN** AI SHALL 提示"该配置超出标准等级"，MR 描述中注明"资源配置超出标准等级 L，需平台团队审批"，reviewer 包含平台团队

#### Scenario: 超额 MR 描述

- **WHEN** AI 创建超额资源的 MR
- **THEN** MR 描述 SHALL 包含：当前配置、请求配置、超出的具体项（CPU/内存）、申请原因（如用户提供）
