# DevOps Skill 开发 — Change 划分

## 划分原则

**底层设计原则：** 所有设计决策以"AI 操作不易出错"为第一判断标准。文件结构为 AI 优化，人需要的视图由 AI 按需生成。

**纵向切片：** 每个 change 同时包含该领域的架构规范和场景设计，而非先做完所有规范再做场景。规范和场景互相验证，问题当场解决。

**按主题划分：** 每个 change 聚焦一个主题，保持讨论边界清晰，便于澄清和 review。

**每个 change 的标准交付物：**
- 该领域的架构规范章节（写入 platform-spec.md）
- 该领域的场景交互设计（写入 flows/*.md）
- 相关待决策项的最终决定
- 验证场景 + 明确的验收条件

---

## 依赖关系

```
Change 1 (平台基础规范 — 厚地基) ✅ 开发完成
    |
    +---> Change 2 (服务生命周期与依赖管理) ✅ 开发完成
    |         |
    |         +---> Change 3 (CI/CD 与部署流程)
    |
    +---> Change 4 (可观测性)
    |
    +---> Change 5 (网络安全与备份)

Change 2~5 完成后
    |
    +---> Change 6 (高级特性)

所有上面完成后
    |
    +---> Change 7 (端到端验收与打磨)
```

---

## Change 1：平台基础规范 ✅ 开发完成

**定位：** 厚地基。整个平台的运行规则，后续所有 change 在此框架内工作。

**状态：** 开发任务全部完成，剩余基础设施相关任务待环境就绪后执行。

**已完成的开发交付物：**
- platform-spec.md — 13 章完整平台规范（目录结构、路径公式、命名规范、环境管理、base/overlay 边界、base 模板、Kustomize patch 模板、资源等级、Secret 命名、所有权模型、GitOps 工作流、重命名流程、.devops.yaml schema）
- skill.md — Skill 骨架（P0-P3 原则、8 步 AI 处理框架、7 种意图分类）
- gitops-repo 初始化 — 三层目录结构、demo 示例、platform-inventory.yaml（5 域：nrtk/ppp-rtk/biz-app/bigdata/tools）、CODEOWNERS、ArgoCD ApplicationSet、CI 脚本模板、JSON Schema、漂移检测脚本
- .devops.yaml JSON Schema 及校验脚本

**已做出的决策：**
- Kustomize（非 Helm）
- base/overlay 环境差异化
- 单配置仓库
- 双集群（non-prod + prod）
- .devops.yaml 为服务唯一声明文件（无 dependencies.yaml）
- 无 team 概念，仅按域（domain）组织
- MCP 操作配置仓库

**待基础设施就绪后执行：**
- 1.5 分支保护配置
- 3.1-3.3, 3.7 ArgoCD 安装与验证
- 4.1-4.3 namespace 创建与网络隔离
- 5.1-5.5 GitOps 联动凭证配置
- 6.5-6.6 CI 直推验证
- 9.1-9.6 端到端验证

---

## Change 2：服务生命周期与依赖管理 ✅ 开发完成

**定位：** 开发者最核心的日常操作。创建服务、管理依赖、下线服务。

**状态：** 开发任务全部完成，剩余 Operator 验证和端到端测试待环境就绪后执行。

**已完成的开发交付物：**
- platform-spec.md 补充 — Secret 命名约定、资源规格等级（S/M/L）、CI 检查规范
- flows/init-service.md — 11 步完整流程（前置检查→代码分析→确认→.devops.yaml→资源等级→冲突检测→生成配置→展示方案→提交→CI 检查→结果）
- flows/add-dependency.md — 8 步流程（owner/producer 创建 + consumer 引用，含跨域处理）
- flows/remove-dependency.md — 6 步流程（consumer 简单移除 + owner 消费方检查）
- flows/decommission.md — 7 步流程（二次确认→依赖分析→消费方处理→逐个确认→MR→手动清理）
- flows/ci-config-check.md — 4 项检查 + 统一 CI 模板

**已做出的决策：**
- Secret：K8s 原生 Secret + Operator 自动生成 + {instance-name}-secret 命名
- 资源规格：S/M/L 三档，超 L 需平台团队审批
- 技术栈：go/java/node/python
- "尽力检查 + 不确定就问"策略

**待基础设施就绪后执行：**
- 1.1-1.2 Operator Secret 命名验证
- 8.1-8.10 端到端验证场景

---

## Change 3：CI/CD 与部署流程

**定位：** 代码提交到上线的完整链路。环境推进策略和数据库变更是重点。

**注意：** Change 1 已完成 CI 脚本模板（直推脚本、MR 创建脚本、diff 校验脚本）和 CI 配置检查（ci-config-check flow）。本 change 聚焦 **环境推进流程** 和 **数据库变更管理**。

**需要做出的决策：**
- 数据库变更工具选型
- 回滚策略（纯代码 vs 带 DB 变更）
- 环境推进审批流程

**交付物：**
- flows/deploy.md（部署与环境推进：dev→test→staging→prod）
- flows/rollback.md（回滚策略，按场景区分）
- flows/db-migration.md（数据库变更管理）
- platform-spec.md 补充（环境推进规范、回滚流程）

**验证场景：**
- 场景 A：纯代码变更，从 push 到 prod 上线完整流程
- 场景 B：带 DB migration 的变更，部署顺序怎么处理？
- 场景 C：上线后发现问题，纯代码回滚
- 场景 D：上线后发现问题，涉及 DB 变更的回滚
- 场景 E：Pipeline 失败，AI 怎么引导？

---

## Change 4：可观测性

**定位：** 让服务"可见"，开发者能自助排查和配告警，不依赖运维。

**需要做出的决策：**
- 日志格式标准
- 告警分级规范
- Metrics/Logs/Traces 技术栈选型

**交付物：**
- flows/observe-alert.md（可观测性与告警配置）
- flows/troubleshoot.md（线上排查引导）
- platform-spec.md 补充（可观测性分层标准、指标命名规范、告警分级）

**验证场景：**
- 场景 A：新服务零配置获得的基础监控
- 场景 B：自然语言配置告警规则
- 场景 C：AI 辅助线上排查
- 场景 D：业务指标埋点

---

## Change 5：网络安全与备份

**定位：** 生产加固。确保服务在生产环境安全、可靠地运行。

**需要做出的决策：**
- 服务间调用方式
- 数据库备份方案
- NetworkPolicy 策略

**交付物：**
- platform-spec.md 补充（NetworkPolicy 模板、备份恢复规范）
- 更新已有 flow：
  - init-service.md 增加 NetworkPolicy 自动生成
  - add-dependency.md 增加中间件访问控制配置

**验证场景：**
- 场景 A：跨域数据库访问控制
- 场景 B：数据恢复流程
- 场景 C：服务间 API 调用网络配置

---

## Change 6：高级特性

**定位：** 锦上添花。核心流程跑通后，按实际痛点决定优先级。

**讨论重点（先决定"是否需要"再讨论"怎么做"）：**
- 灰度发布：原生滚动更新 vs 金丝雀
- 本地开发：docker-compose vs telepresence
- 多集群扩展（当前双集群是否足够）

**交付物：**
- flows/local-dev.md（本地开发环境配置）
- 灰度发布方案（如确认需要）

---

## Change 7：端到端验收与打磨

**定位：** 把前面所有成果串起来验收、发现缝隙、打磨体验。

**内容：**
- 用真实项目从头到尾走一遍完整流程
- 发现各 change 之间的衔接问题并修复
- 打磨 skill.md 的意图识别和场景分发逻辑
- 补充 examples/
- 确认所有 flow 的交互体验符合 P0-P3 原则

**端到端验证流程：**
```
1. 新建服务（Change 2）
   "帮我创建一个 order-service，Go 语言，需要 MySQL 和 Kafka"
       |
2. 本地开发（Change 6）
   "怎么在本地跑起来？"
       |
3. 提交代码（Change 3）
   push 代码 → CI 运行 → 镜像构建 → 部署到 dev
       |
4. 加监控（Change 4）
   "帮我加个告警，接口 P99 超过 500ms 就报警"
       |
5. 推进到 prod（Change 3）
   "部署到生产环境"
       |
6. 模拟故障（Change 4）
   "线上 5xx 增多，帮我排查"
       |
7. 回滚（Change 3）
   "帮我回滚到上个版本"
       |
8. 加新依赖（Change 2）
   "需要加一个 Redis 缓存"
       |
9. 另一个服务消费 Kafka（Change 2）
   "我要消费 order-events 这个 topic"
```

---

## 执行顺序

```
顺序    Change                  状态           前置依赖
----    ------                  ----           --------
 1      平台基础规范             ✅ 开发完成    无
 2      服务生命周期与依赖管理    ✅ 开发完成    Change 1
 3      CI/CD 与部署流程         待开始         Change 2
 4      可观测性                 待开始         Change 1
 5      网络安全与备份            待开始         Change 1
 6      高级特性                 待开始         Change 2~5
 7      端到端验收与打磨          待开始         全部

Change 3/4/5 之间无强依赖，可按优先级调整顺序。
建议 Change 3 优先（部署流程是开发者下一个最关心的事）。
Change 4 和 5 可并行或按需调整。
```
