# DevOps 平台项目

## 语言

始终使用中文与用户交互。

## 项目约定

- `devops-platform-plan.md` 是早期初稿，后续 OpenSpec artifact（proposal/design/spec）优先级更高。Review 发现 plan 与最新 artifact 不一致时，提示用户确认后再更新 plan，不作为阻塞项。

## 已知待办

- **AppSet syncPolicy 按环境区分**：`gitops-repo/argocd/appset.yaml` 当前所有环境都用 `automated: { selfHeal: true }`，spec 要求 dev 自动同步、test/staging/prod 手动同步。部署到真实集群前需拆成 dev 和 non-dev 两组 ApplicationSet（共 4 个）。注意 ArgoCD 中 selfHeal 是 auto-sync 的子功能，关闭 automated 就没有 selfHeal，需评估替代方案。
