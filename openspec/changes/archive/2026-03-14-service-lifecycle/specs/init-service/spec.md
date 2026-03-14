## ADDED Requirements

### Requirement: init-service 前置条件检查

AI 执行 init-service 前 SHALL 按顺序检查以下前置条件，任一不满足则停止执行：

| 顺序 | 检查项 | 判断方式 | 不满足时行为 |
|------|--------|---------|-------------|
| 1 | MCP 可用 | 尝试调用 MCP git 工具 | 输出 MCP 安装指引，停止执行 |
| 2 | 代码仓库非空 | 检查是否有实际代码文件（不仅是 README/.gitignore） | 提示"请先完成代码开发，再运行 /devops 初始化"，停止执行 |
| 3 | 未重复初始化 | 检查 .devops.yaml 是否已存在 | 提示"当前仓库已接入 DevOps 平台"，引导其他操作 |

#### Scenario: MCP 未配置

- **WHEN** 开发者运行 `/devops` 初始化服务，但 MCP 未安装或未配置 git 工具
- **THEN** AI SHALL 输出 MCP 安装指引（安装命令 + git 工具配置示例），提示"安装完成后重新运行 /devops"，停止执行

#### Scenario: 代码仓库为空

- **WHEN** 开发者运行 `/devops` 初始化服务，但代码仓库只有 README.md 和 .gitignore
- **THEN** AI SHALL 提示"当前仓库没有实际代码，请先完成代码开发，再运行 /devops 初始化"，停止执行

#### Scenario: 已有 .devops.yaml

- **WHEN** 开发者运行 `/devops` 初始化服务，但 .devops.yaml 已存在
- **THEN** AI SHALL 提示"当前仓库已接入 DevOps 平台（服务名：{name}）"，并引导其他操作（如添加依赖、部署等）

---

### Requirement: 代码分析与信息推断

AI SHALL 分析代码仓库内容，自动推断服务的关键信息。所有推断结果 MUST 经用户逐项确认后才能写入。

推断规则：

| 信息 | 推断方式 | 推断失败时 |
|------|---------|-----------|
| 服务名 | 目录名 / go.mod module / package.json name | 让用户指定 |
| 语言 | go.mod→go, pom.xml→java, package.json→node, requirements.txt→python | 让用户指定 |
| 端口 | 代码中的 Listen/Server 配置 | 默认提示 8080，让用户确认 |
| 健康检查 | 路由中的 /health 或 /healthz | 默认 /healthz，让用户确认 |
| 慢启动 | language=java 时推荐 true | 默认 false |
| 依赖 | import 路径（database/sql→MySQL）、配置文件（redis://） | 初始化时可不添加 |

#### Scenario: AI 推断 Go 服务信息

- **WHEN** 代码仓库包含 go.mod（module 为 company.com/trade/order-service），main.go 中有 `http.ListenAndServe(":8080", ...)`
- **THEN** AI SHALL 推断服务名为 order-service、语言为 go、端口为 8080，逐项展示并要求用户确认

#### Scenario: AI 推断 Java 服务并推荐慢启动

- **WHEN** 代码仓库包含 pom.xml，未设置 slow_start
- **THEN** AI SHALL 推断语言为 java，并额外提示"Java 服务通常启动较慢，建议设置 slow_start: true 以启用 startupProbe，是否添加？"

#### Scenario: 推断失败

- **WHEN** 代码仓库不包含任何已知的语言特征文件
- **THEN** AI SHALL 提示"无法自动检测编程语言，请指定：go/java/node/python"

#### Scenario: 检测到已有依赖

- **WHEN** 代码中 import 了 `database/sql` 或配置文件中有 MySQL 连接字符串
- **THEN** AI SHALL 提示"检测到 MySQL 依赖，是否添加到 dependencies？如果是，请确认资源名称和角色（owner/consumer）"

---

### Requirement: 域和团队信息收集

AI SHALL 引导用户指定域和团队信息。域 MUST 在 platform-inventory.yaml 中存在。

#### Scenario: 引导选择域

- **WHEN** AI 收集服务的域信息
- **THEN** AI SHALL 从 platform-inventory.yaml 读取所有可用域，展示列表让用户选择，不得让用户自由输入

#### Scenario: 域选择后自动填充团队

- **WHEN** 用户选择域为 trade
- **THEN** AI SHALL 从 platform-inventory.yaml 中自动填充 team 为 trade-team（域对应的团队），展示并让用户确认

#### Scenario: 负责人信息

- **WHEN** AI 收集服务负责人
- **THEN** AI SHALL 询问"请输入服务负责人姓名"，不得自动推断

---

### Requirement: .devops.yaml 生成

确认所有信息后，AI SHALL 在代码仓库根目录生成 .devops.yaml 文件，包含 service、gitops、runtime、dependencies 四个顶层字段。

#### Scenario: 生成完整 .devops.yaml

- **WHEN** 用户确认了所有信息：name=order-service, domain=trade, team=trade-team, owner=zhangsan, language=go, port=8080
- **THEN** AI SHALL 生成 .devops.yaml：
  ```yaml
  service:
    name: order-service
    domain: trade
    team: trade-team
    owner: zhangsan
  gitops:
    repo: https://gitlab.company.com/infra/gitops-repo
    path: services/trade/order-service
  runtime:
    language: go
    port: 8080
    health_check: /healthz
  dependencies: []
  ```

#### Scenario: gitops 字段自动填充

- **WHEN** AI 生成 .devops.yaml 的 gitops 字段
- **THEN** AI SHALL 从 platform-inventory.yaml 的 gitlab.gitops_repo 和 gitlab.url 自动拼接 gitops.repo，按 `services/{domain}/{service}` 自动生成 gitops.path，展示给用户确认

---

### Requirement: 配置仓库文件生成

AI SHALL 通过 MCP clone 配置仓库，创建服务的完整目录结构和配置文件，并创建 MR。

#### Scenario: 创建服务目录结构

- **WHEN** AI 为 trade 域的 order-service 生成配置仓库文件
- **THEN** AI SHALL 创建以下目录和文件：
  ```
  services/trade/order-service/
  ├── base/
  │   ├── deployment.yaml
  │   ├── service.yaml
  │   ├── ingress.yaml
  │   └── kustomization.yaml
  └── overlays/
      ├── dev/kustomization.yaml
      ├── test/kustomization.yaml
      ├── staging/kustomization.yaml
      └── prod/kustomization.yaml
  ```

#### Scenario: 同时创建 owner 依赖的资源目录

- **WHEN** 初始化时 dependencies 包含 `{name: order-db, type: mysql, role: owner}`
- **THEN** AI SHALL 同时创建 `resources/trade/mysql/order-db/` 的 base 和 overlays 目录结构

#### Scenario: 服务名冲突检测

- **WHEN** AI 准备创建 `services/trade/order-service/` 但该目录已存在
- **THEN** AI SHALL 报错"服务 order-service 在 trade 域中已存在，不能重复创建"，停止执行

#### Scenario: 创建前展示变更方案

- **WHEN** AI 准备创建配置仓库文件
- **THEN** AI SHALL 先展示将要创建的完整文件列表和关键配置内容（deployment 的 container/ports/probes、overlay 的 namespace/images），等用户确认后再执行

#### Scenario: 创建 MR

- **WHEN** 用户确认变更方案
- **THEN** AI SHALL 通过 MCP 创建新分支，commit 所有文件，push 并创建 MR。MR 描述 SHALL 包含：操作发起人、"初始化服务 {service-name}"意图、创建的文件列表

---

### Requirement: 初始化完成后展示结果

AI SHALL 在初始化完成后展示操作结果和下一步指引。

#### Scenario: 展示初始化结果

- **WHEN** init-service 流程完成
- **THEN** AI SHALL 展示：
  1. .devops.yaml 已创建（在代码仓库）
  2. 配置仓库 MR 链接
  3. CI 配置检查结果（见 ci-config-check capability）
  4. 下一步建议："MR 合并后，push 代码即可自动部署到 dev 环境"
