## MODIFIED Requirements

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
| migration 路径 | 扫描常见目录：db/migration/、migrations/、sql/ | 不设置（不启用 migration） |

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

#### Scenario: AI 推断 migration 路径

- **WHEN** 代码仓库存在 `db/migration/` 目录且包含 `V*.sql` 文件
- **THEN** AI SHALL 推断 migration_path 为 `db/migration`，展示"检测到数据库 migration 目录（db/migration/），是否启用 Flyway init container 自动执行 migration？"并要求用户确认

#### Scenario: 多个候选 migration 目录

- **WHEN** 代码仓库同时存在 `db/migration/` 和 `migrations/` 目录
- **THEN** AI SHALL 列出候选目录让用户选择，不得自行决定

#### Scenario: 无 migration 目录

- **WHEN** 代码仓库不存在任何常见 migration 目录
- **THEN** AI SHALL 不设置 migration_path（不启用 migration），不主动询问
