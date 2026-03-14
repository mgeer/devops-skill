## 1. Secret 管理规范

- [ ] 1.1 确定各 Operator 的 Secret 生成配置，确保命名遵循 `{instance-name}-secret` 约定（MySQL Operator、Redis Operator）
- [ ] 1.2 验证 Operator 生成的 Secret 包含约定的 key（MYSQL_HOST/PORT/USER/PASSWORD/DATABASE、REDIS_HOST/PORT/PASSWORD）
- [x] 1.3 在 platform-spec.md 中新增 Secret 命名约定章节（命名规则、各类型包含的 key、envFrom 注入方式）
- [x] 1.4 编写 envFrom secretRef 的标准 Kustomize patch 模板，加入 platform-spec.md

## 2. 资源规格定义

- [x] 2.1 在 platform-spec.md 中新增资源规格等级章节（S/M/L 三档的 CPU/内存配置、适用场景、默认推荐 M）
- [x] 2.2 编写资源规格的标准 Kustomize patch 模板（S/M/L 各一个），加入 platform-spec.md
- [x] 2.3 在 platform-spec.md 中定义超额审批规则（超出 L 时 MR 需添加平台团队 reviewer）

## 3. init-service flow 实现

- [x] 3.1 编写 flows/init-service.md：定义完整交互流程（前置检查 → 代码分析 → 信息确认 → .devops.yaml 生成 → 配置仓库文件生成 → CI 检查 → 结果展示）
- [x] 3.2 定义代码分析推断规则（语言检测、端口推断、健康检查推断、依赖检测的具体文件和模式）
- [x] 3.3 定义域和团队信息收集逻辑（从 platform-inventory.yaml 读取可用域列表、域→团队自动映射）
- [x] 3.4 定义 .devops.yaml 生成模板（包含 gitops 字段自动填充逻辑）
- [x] 3.5 定义配置仓库文件生成规则（base 目录文件列表、overlay 目录文件列表、资源规格选择、含 owner 依赖时同时创建 resources 目录）
- [x] 3.6 定义冲突检测逻辑（同名服务检查、同名资源检查）
- [x] 3.7 定义 MR 创建规范（分支命名、commit message、MR 描述模板）

## 4. add-dependency flow 实现

- [x] 4.1 编写 flows/add-dependency.md：定义完整交互流程（前置检查 → 类型选择 → 角色确认 → owner/consumer 分支 → 变更同步）
- [x] 4.2 定义 owner/producer 操作逻辑（资源名生成、冲突检查、资源目录创建、环境变量注入规则）
- [x] 4.3 定义 consumer 操作逻辑（资源存在性验证、环境变量引用添加、跨域依赖提示、跨域时 domain 字段必填）
- [x] 4.4 定义 .devops.yaml dependencies 更新逻辑（新增条目、去重检查、domain 字段处理）
- [x] 4.5 定义各类型中间件的环境变量注入标准（MySQL→envFrom secretRef、Redis→envFrom secretRef、Kafka→KAFKA_BOOTSTRAP env）
- [x] 4.6 定义 remove-dependency 流程（consumer 移除：删条目+移除 env 引用；owner 移除：检查消费方+删资源目录）

## 5. decommission flow 实现

- [x] 5.1 编写 flows/decommission.md：定义完整交互流程（意图确认 → 依赖影响分析 → 有依赖时阻止 → 分步清理 → MR 创建 → 手动清理提示）
- [x] 5.2 定义依赖影响分析逻辑（"尽力检查 + 不确定就问"策略：MySQL/Redis 通过 secretRef 反查、Kafka 询问用户、区分可删除和不可删除资源）
- [x] 5.3 定义分步清理顺序和确认逻辑（逐个资源确认 → 服务目录确认）
- [x] 5.4 定义跨域依赖通知逻辑（识别 consumer 所属域和团队、生成联系建议）
- [x] 5.5 定义手动清理事项清单模板（.devops.yaml 删除、CI 配置清理、ArgoCD 同步说明）

## 6. CI 配置检查

- [x] 6.1 定义 CI 检查项的具体检测逻辑（.gitlab-ci.yml 存在性、部署步骤关键字匹配、镜像 tag 格式检查、Harbor 地址匹配）
- [x] 6.2 定义 CI 配置生成模板（按语言区分：Go/Java/Node/Python 的基础 CI 配置，均包含构建镜像 → 推送 Harbor → 更新配置仓库步骤）
- [x] 6.3 在 flows/init-service.md 中整合 CI 检查步骤（检查结果展示、生成/优化引导）

## 7. Skill 骨架更新

- [x] 7.1 更新 skill.md：在 AI 处理逻辑框架中新增 MCP 可用性检查（步骤 1）和代码仓库状态检查（步骤 3）
- [x] 7.2 更新 skill.md：在意图识别分类中新增 init-service、add-dependency、remove-dependency、decommission、ci-config-check 五种意图及对应 flow 引用
- [x] 7.3 更新 platform-spec.md：新增 Secret 命名约定、资源规格定义、CI 检查规范章节

## 8. 端到端验证

- [ ] 8.1 验证场景 A：模拟 init-service — 新建 Go 服务（order-service），需要 MySQL（owner）+ Kafka topic（producer），走完完整流程确认 .devops.yaml 和配置仓库文件正确
- [ ] 8.2 验证场景 B：模拟 add-dependency — 另一个服务（notification-service）消费 order-service 的 Kafka topic（consumer），确认跨服务引用正确
- [ ] 8.3 验证场景 C：模拟 decommission — 尝试下线 order-service（有 consumer 的 Kafka topic），确认阻止删除逻辑正确
- [ ] 8.4 验证场景 D：模拟 init-service — 代码仓库为空时，确认提示并停止
- [ ] 8.5 验证场景 E：模拟 add-dependency — 需要的中间件 Operator 未部署（available=false），确认提示正确
- [ ] 8.6 验证场景 F：模拟 init-service — 选择超出 L 等级的资源规格，确认 MR 添加平台团队 reviewer
- [ ] 8.7 验证 Secret 链路：Operator 创建 MySQL 实例 → 自动生成 Secret → deployment envFrom 引用 → Pod 环境变量注入
- [ ] 8.8 验证场景 G：模拟 remove-dependency — 移除 consumer 依赖（notification-service 移除 order-events 消费），确认 overlay 和 .devops.yaml 正确更新
- [ ] 8.9 验证场景 H：模拟 remove-dependency — 移除 owner 依赖（order-service 移除 order-cache），确认资源目录被删除
- [ ] 8.10 验证场景 I：模拟跨域 consumer — user 域服务消费 trade 域 Kafka topic，确认 domain 字段正确处理
