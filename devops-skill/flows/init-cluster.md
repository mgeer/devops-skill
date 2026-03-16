# Flow: init-cluster — 集群环境探测与配置

## 触发条件
- 用户意图：初始化集群、添加集群、集群探测
- 前置条件：platform-config.yaml 已存在 + gitlab/registry 已填写

---

## 完整流程

### Step 1: 前置检查

```
检查项                | 条件                                    | 不满足时
platform-config.yaml | 存在且 gitlab/registry 已填写              | 提示先完成基础配置，停止
kubeconfig 可用       | 指定路径的 kubeconfig 存在且可访问集群       | 提示检查路径和权限，停止
kubectl 连通          | kubectl get nodes 成功                    | 提示检查集群连接，停止
```

### Step 2: 集群环境探测

AI 通过 kubectl 自动探测以下信息：

#### 2.1 节点架构

```bash
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}'
```

| 结果 | 记录值 |
|------|--------|
| `amd64` | arch: amd64 |
| `arm64` | arch: arm64 |
| 混合 | arch: multi（提示用户确认构建目标） |

#### 2.2 网络连通性

在集群内运行临时 Pod 测试 DNS 解析：

```bash
kubectl run net-test --rm --restart=Never --image=busybox \
  --command -- nslookup pypi.org
```

| 结果 | 记录值 |
|------|--------|
| 解析成功 | network: online |
| 解析失败 / 超时 | network: offline |

> 测试用的 busybox 镜像需要先确认 registry 中可用，否则使用 registry 中已有的任意镜像代替。

#### 2.3 Ingress 控制器检测

按优先级检查：

```
1. kubectl get pods --all-namespaces | grep ingress
2. kubectl get pods --all-namespaces | grep traefik
3. kubectl get ingressclass
4. kubectl get crd | grep traefik
```

| 发现 | 记录值 |
|------|--------|
| traefik pod 存在 | class: traefik |
| nginx-ingress pod 存在 | class: nginx |
| 都不存在 | 提示用户手动指定 |

#### 2.4 Traefik 详细探测（当 class=traefik 时）

```bash
# 获取版本
kubectl get pods -n {namespace} -l {traefik-label} \
  -o jsonpath='{.items[0].spec.containers[0].image}'

# 获取 entrypoints
kubectl get configmap {traefik-config} -n {namespace} \
  -o jsonpath='{.data.traefik\.yaml}'
# 解析 entryPoints 块

# 获取端口映射
kubectl get daemonset/deployment {traefik} -n {namespace} \
  -o jsonpath='{.spec.template.spec.containers[0].ports}'
```

记录所有 entrypoint 的 name、containerPort、hostPort、是否 TLS。

#### 2.5 Nginx Ingress 详细探测（当 class=nginx 时）

```bash
# 获取 IngressClass 名称
kubectl get ingressclass -o jsonpath='{.items[*].metadata.name}'

# 获取 Service 端口
kubectl get svc -n {namespace} {nginx-ingress-controller} \
  -o jsonpath='{.spec.ports}'
```

#### 2.6 Master 节点 EIP 探测

```bash
kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[*].status.addresses}'
```

提取 ExternalIP 或由用户提供 EIP。

#### 2.7 K8s API Server 地址

```bash
kubectl cluster-info | grep 'Kubernetes control plane'
```

### Step 3: 展示探测结果，逐项确认

```
集群环境探测完成：

  集群名称:    [请命名，如 dev-cluster]
  API Server:  https://10.66.65.53:6443
  节点架构:    amd64（来源: kubectl get nodes）
  网络模式:    offline（来源: DNS 解析测试失败）
  Master EIP:  10.66.67.141, 10.66.64.216

  Ingress 控制器:
    类型:       traefik（来源: kube-system 中发现 traefik pod）
    版本:       v2.11.24
    入口点:
      - web:       port 80,  HTTP
      - websecure: port 1443, HTTPS
    默认入口点:  web

  kubeconfig:  ~/.kube/config

请逐项确认或修改。

还需要你提供：
  - 集群逻辑名称（如 dev-cluster）
  - 此集群对应的环境（int / test / staging / prod，可多选）
```

**每项探测结果 MUST 经用户确认。**

### Step 4: 环境映射配置

用户选择此集群对应的环境后，生成 environments 映射：

```
你选择了此集群对应环境：int, test

建议的环境配置：
  int:     auto_deploy=true,  approval=none
  test:    auto_deploy=false, approval=reviewer

确认？
```

### Step 5: 写入 platform-config.yaml

将确认后的信息写入 gitops-repo 的 `platform-config.yaml`：

**clusters 块：**
```yaml
clusters:
  {cluster-name}:
    display_name: "{用户确认的显示名}"
    kubeconfig: "{kubeconfig 路径}"
    api_server: "{探测到的 API Server}"
    arch: "{探测到的架构}"
    network: "{探测到的网络模式}"
    master_eips:
      - "{探测到或用户提供的 EIP}"
    ingress:
      class: "{探测到的 ingress 类型}"
      entrypoints:
        - name: "{entrypoint 名}"
          port: {端口}
          tls: {true/false}
      default_entrypoint: "{默认入口点}"
```

**environments 块：**
```yaml
environments:
  {env}:
    cluster: "{cluster-name}"
    auto_deploy: {true/false}
    approval: "{审批级别}"
```

### Step 6: 镜像架构校验

当 network=offline 时，检查 registry 中基础镜像的架构是否匹配：

```
检查 Harbor 中基础镜像架构:

  python:3.11-slim    amd64  ✓ 匹配
  node:18-alpine      arm64  ✗ 不匹配！需要推送 amd64 版本
  nginx:alpine        arm64  ✗ 不匹配！需要推送 amd64 版本

是否现在修复不匹配的镜像？（需要本机有外网访问）
```

修复方式：
```bash
skopeo copy --override-arch {target_arch} --override-os linux \
  docker://docker.io/library/{image}:{tag} \
  docker://{registry}/{project}/{image}:{tag} \
  --dest-tls-verify=false --dest-creds "{user}:{pass}"
```

### Step 7: 展示结果与下一步

```
✓ 集群 {cluster-name} 初始化完成

已写入 platform-config.yaml:
  - clusters.{cluster-name}（架构、网络、Ingress 等）
  - environments.{env}（环境映射）

集群特征摘要:
  - 离线集群 → CI 构建将使用 deps 镜像模式
  - Traefik Ingress → 服务入口将生成 IngressRoute CRD
  - 基础镜像架构已校验/修复

下一步:
  1. 如需添加更多集群，再次运行 /devops 初始化集群
  2. 运行 /devops 初始化服务，开始部署第一个应用
```

---

## 注意事项

- 探测过程中所有 kubectl 命令使用指定的 kubeconfig
- 探测用的临时 Pod 完成后 MUST 清理
- 已存在的集群配置可重新探测覆盖（用户确认后）
- kubeconfig 路径不写入 gitops 仓库（安全），仅存在本地 platform-config 副本中
