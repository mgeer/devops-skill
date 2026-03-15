# DevOps 平台项目

## 语言

始终使用中文与用户交互。

## 项目约定

- `devops-platform-plan.md` 是早期初稿，后续 OpenSpec artifact（proposal/design/spec）优先级更高。Review 发现 plan 与最新 artifact 不一致时，提示用户确认后再更新 plan，不作为阻塞项。

## 项目状态

- **/devops skill 核心开发完成**（Change 1-3 全部完成），等待真实集群环境验证（K8s + ArgoCD + MCP 联调 + Operator Secret 验证）。不要再规划新 Change。
- **SRP 拆分决策**：可观测性和安全不属于 /devops，将来单独做 skill（/observe、/security）。不要往 /devops 里加监控、告警、NetworkPolicy、备份相关的 flow。
- **灰度发布**是 Change 3 (deploy flow) 的未来扩展方向，按需再做。
- **行为测试框架**已建立（`tests/`），6/6 测试通过。修改 skill flow 或 platform-spec 模板后可重新运行验证。过程中修复了 validate-devops-yaml.sh 和 detect-drift.sh 共 3 个 bug（macOS 兼容性 + 字段提取）。

## 已知待办

- **AppSet syncPolicy 按环境区分**：`gitops-repo/argocd/appset.yaml` 当前所有环境都用 `automated: { selfHeal: true }`，spec 要求 dev 自动同步、test/staging/prod 手动同步。部署到真实集群前需拆成 dev 和 non-dev 两组 ApplicationSet（共 4 个）。注意 ArgoCD 中 selfHeal 是 auto-sync 的子功能，关闭 automated 就没有 selfHeal，需评估替代方案。
