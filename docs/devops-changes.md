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
              |
              +---> Change 3 (CI/CD 与部署流程) ✅ 开发完成
```

/devops skill 核心开发完成。

> **不在 /devops 范围内，将来单独做 skill：**
> - **可观测性** — 监控、告警、日志、链路追踪、排查 → /observe skill
> - **安全** — NetworkPolicy、服务间调用控制、数据库备份恢复 → /security skill（或平台团队基础设施管理）
>
> **Change 3 未来扩展方向：**
> - **灰度发布** — 当原生滚动更新不够用时，扩展 deploy flow 支持金丝雀发布

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

## Change 3：CI/CD 与部署流程 ✅ 开发完成

**定位：** 环境推进流程和数据库变更管理。推进+回滚合一个 flow，DB migration 作为执行基础设施按需启用。

**状态：** 开发任务全部完成（20/20），验证通过。

**已完成的开发交付物：**
- flows/deploy.md — 推进+回滚合一（6 步推进 + 6 步回滚，含 migration 文件变更检测）
- platform-spec.md 补充 — §12 DB Migration 执行规范（Flyway CLI、forward-only 策略、init container 模板、条件逻辑）
- .devops.yaml schema 新增 `runtime.migration_path` 可选字段
- validate-devops-yaml.sh 新增 migration_path + mysql owner 依赖检查
- skill.md 意图识别新增 deploy/rollback 意图
- flows/init-service.md 新增 migration 路径推断逻辑

**已做出的决策：**
- DB migration 工具：Flyway CLI（统一跨语言，纯 SQL）
- Migration 策略：Forward-only，不支持 DOWN migration（expand-contract 模式）
- 执行方式：Init container 按需注入（有 migration_path 且有 mysql owner 时才加）
- Migration 路径：AI 推断 + 记入 .devops.yaml（一个字段兼做开关）
- 提醒原则：信息搬运，AI 只列出变更文件，明确声明"无法判断兼容性"
- DB 连接：复用 Operator 已有 Secret，secretKeyRef 逐字段引用
- 推进+回滚合一个 flow（机制相同，只是方向不同）

**待基础设施就绪后执行：**
- 端到端验证（已通过走读验证，需集群实测）

---

## 执行顺序

```
顺序    Change                  状态           前置依赖
----    ------                  ----           --------
 1      平台基础规范             ✅ 开发完成    无
 2      服务生命周期与依赖管理    ✅ 开发完成    Change 1
 3      CI/CD 与部署流程         ✅ 开发完成    Change 2
```

/devops skill 核心开发完成。后续按需迭代。
