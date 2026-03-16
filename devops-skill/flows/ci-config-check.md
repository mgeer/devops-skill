# Flow: CI 配置检查

## 定位
Skill 不主动生成 CI 配置。只在 init-service 最后一步检查合理性，有问题时询问用户是否需要帮助。

---

## 检查项

### 1. CI 文件存在性
```
检查: .gitlab-ci.yml 是否存在
不存在 → "未检测到 CI 配置。push 代码后不会自动构建和部署。是否需要帮你生成基础 CI 配置？"
```

### 2. 部署步骤
```
检查: CI 配置中是否包含更新配置仓库镜像 tag 的步骤
关键字匹配: gitops-repo、newTag、deploy、DEPLOY_TOKEN
不存在 → "CI 配置中未检测到部署步骤。push 代码后不会自动触发 int 部署。是否需要帮你添加？"
```

### 3. 镜像 tag 格式
```
检查: 镜像 tag 是否使用 git sha
关键字匹配: CI_COMMIT_SHORT_SHA、CI_COMMIT_SHA、git rev-parse
不匹配 → "建议使用 git sha 作为镜像 tag（如 $CI_COMMIT_SHORT_SHA），确保每次构建唯一可追溯。"
```

### 4. Harbor 推送地址
```
检查: 镜像推送地址是否指向正确的 Harbor 项目
期望: harbor.company.com/{domain}/{service}
不匹配 → "镜像推送地址应为 harbor.company.com/{domain}/{service}，当前配置可能不正确。"
```

### 5. Migration 一致性（仅当 dependencies 含 mysql role=owner 时检查）

| 检查项 | 条件 | 级别 | 提示 |
|--------|------|------|------|
| migration 未配置 | 有 MySQL owner 但 `.devops.yaml` 无 `runtime.migration_command` | WARN | "有 MySQL owner 依赖但未配置 migration，部署时不会自动初始化数据库 schema。建议配置 `runtime.migration_command`。" |
| Dockerfile 缺失 migration 工具 | 有 `migration_command` 但 Dockerfile 中未安装对应工具（如 Python 项目无 `alembic`） | WARN | "migration_command 配置了 `{command}` 但 Dockerfile 中未发现对应工具安装步骤，initContainer 可能执行失败。" |

---

## CI 配置生成模板

当用户请求帮助生成时，按语言提供基础模板。所有模板 MUST 包含三个 stage：test → build → deploy。

### Test stage（按语言选择）

| 语言 | image | script |
|------|-------|--------|
| go | `golang:1.22` | `go test ./...` |
| java | `maven:3.9-eclipse-temurin-21` | `mvn test` |
| node | `node:20` | `npm ci && npm test` |
| python | `python:3.12` | `pip install -r requirements.txt && pytest` |

### Build + Deploy stage（所有语言通用）

```yaml
stages:
  - test
  - build
  - deploy

test:
  stage: test
  image: {见上方语言表}
  script:
    - {见上方语言表}

build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t harbor.company.com/{domain}/{service}:${CI_COMMIT_SHORT_SHA} .
    - docker login -u ${HARBOR_USER} -p ${HARBOR_PASSWORD} harbor.company.com
    - docker push harbor.company.com/{domain}/{service}:${CI_COMMIT_SHORT_SHA}
  only:
    - main

deploy-int:
  stage: deploy
  image: alpine/git:latest
  script:
    - git clone "https://${DEPLOY_TOKEN_USER}:${DEPLOY_TOKEN}@gitlab.company.com/infra/gitops-repo.git" /tmp/gitops-repo
    - cd /tmp/gitops-repo
    - "sed -i 's/newTag: \".*\"/newTag: \"'${CI_COMMIT_SHORT_SHA}'\"/' services/{domain}/{service}/overlays/int/kustomization.yaml"
    - git add .
    - git commit -m "ci: update {service} image to ${CI_COMMIT_SHORT_SHA}"
    - |
      for i in 1 2 3; do
        git push origin main && break
        git pull --rebase origin main
      done
  only:
    - main
```

---

## 生成时的变量替换

模板中的 `{domain}` 和 `{service}` 从 `.devops.yaml` 读取，替换后展示给用户确认。

CI 配置生成后提示：
```
CI 配置已生成。请确认以下 CI 变量已在 GitLab 项目中配置:
  - HARBOR_USER — Harbor Robot Account 用户名
  - HARBOR_PASSWORD — Harbor Robot Account 密码
  - DEPLOY_TOKEN_USER — GitLab Deploy Token 用户名
  - DEPLOY_TOKEN — GitLab Deploy Token
```
