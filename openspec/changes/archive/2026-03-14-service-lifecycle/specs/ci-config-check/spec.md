## ADDED Requirements

### Requirement: CI 配置检查时机

AI SHALL 在 init-service 流程的最后一步执行 CI 配置检查。此检查不阻塞初始化流程。

#### Scenario: init-service 完成后检查 CI

- **WHEN** init-service 的配置仓库 MR 创建完成
- **THEN** AI SHALL 自动检查当前代码仓库的 .gitlab-ci.yml，展示检查结果

#### Scenario: 独立触发 CI 检查

- **WHEN** 开发者说"帮我检查一下 CI 配置"
- **THEN** AI SHALL 读取 .gitlab-ci.yml 并执行检查

---

### Requirement: CI 配置检查项

AI SHALL 检查以下关键项，每项给出通过/不通过/缺失的结果：

| 检查项 | 检查内容 | 重要性 |
|--------|---------|--------|
| CI 文件存在 | .gitlab-ci.yml 是否存在 | 必须 |
| 部署步骤 | 是否有更新配置仓库镜像 tag 的步骤 | 必须 |
| 镜像命名 | 镜像 tag 是否使用 git sha | 建议 |
| Harbor 推送 | 是否推送到正确的 Harbor 项目 | 建议 |

#### Scenario: CI 文件不存在

- **WHEN** 代码仓库中没有 .gitlab-ci.yml
- **THEN** AI SHALL 提示"未检测到 CI 配置文件（.gitlab-ci.yml）。没有 CI 配置，代码推送后不会自动构建和部署。是否需要帮你生成基础 CI 配置？"

#### Scenario: CI 缺少部署步骤

- **WHEN** .gitlab-ci.yml 存在但没有更新配置仓库镜像 tag 的步骤
- **THEN** AI SHALL 提示"CI 配置中未检测到部署步骤（更新配置仓库镜像 tag）。代码推送后可以构建镜像，但不会自动触发 dev 环境部署。是否需要帮你添加部署步骤？"

#### Scenario: 镜像命名不规范

- **WHEN** .gitlab-ci.yml 中镜像 tag 使用 latest 或固定字符串
- **THEN** AI SHALL 建议"推荐使用 git sha 短哈希作为镜像 tag（如 `$CI_COMMIT_SHORT_SHA`），以确保版本可追溯"

#### Scenario: Harbor 地址不匹配

- **WHEN** .gitlab-ci.yml 中的镜像推送地址不是 `harbor.company.com/{domain}/{service}`
- **THEN** AI SHALL 提示"镜像推送地址应为 harbor.company.com/{domain}/{service}，当前配置的地址可能不匹配，请确认"

#### Scenario: 所有检查通过

- **WHEN** .gitlab-ci.yml 存在且包含正确的部署步骤、镜像命名、Harbor 推送
- **THEN** AI SHALL 提示"CI 配置检查通过，代码推送后将自动构建并部署到 dev 环境"

---

### Requirement: CI 配置生成/优化引导

当 CI 配置缺失或有问题时，用户请求帮助后 AI SHALL 根据代码分析结果生成或优化 CI 配置。

#### Scenario: 用户请求生成 CI 配置

- **WHEN** 检查发现 .gitlab-ci.yml 不存在，用户回答"是，帮我生成"
- **THEN** AI SHALL 根据 runtime.language 生成适合该服务的基础 CI 配置，MUST 包含：构建镜像 → 推送 Harbor → 更新配置仓库 dev overlay newTag

#### Scenario: 用户请求优化 CI 配置

- **WHEN** 检查发现 CI 缺少部署步骤，用户回答"帮我添加"
- **THEN** AI SHALL 在现有 .gitlab-ci.yml 中添加部署步骤，不修改已有的构建/测试阶段

#### Scenario: 用户拒绝帮助

- **WHEN** 检查发现问题，用户回答"不需要，我自己处理"
- **THEN** AI SHALL 记录检查结果，继续后续流程，不阻塞

#### Scenario: 主动请求生成 CI 配置

- **WHEN** 开发者说"帮我生成 CI 配置"（非 init-service 流程中）
- **THEN** AI SHALL 分析代码仓库，根据语言和框架生成 CI 配置，包含部署步骤
