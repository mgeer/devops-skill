## feat: promote order-service to test

### 发起人

zhangsan（服务 owner）

### 意图

将 order-service 部署到 test 环境，镜像 tag 从 `latest` 更新为 `v1.2.3`。

### 影响范围

- **服务：** order-service
- **业务域：** trade
- **目标环境：** test（namespace: `test-trade`）
- **变更内容：** 更新 `services/trade/order-service/overlays/test/kustomization.yaml` 中 `images[].newTag` 从 `latest` 改为 `v1.2.3`
- **数据库变更：** 无（该服务未配置 migration_path）

### 变更文件

| 文件路径 | 变更类型 | 说明 |
|---------|---------|------|
| `services/trade/order-service/overlays/test/kustomization.yaml` | 修改 | newTag: "latest" -> "v1.2.3" |

### 审批要求

test 环境需要团队内 review。

### 部署方式

MR 合并后，ArgoCD 将在手动同步时部署到 test 环境。
