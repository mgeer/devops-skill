#!/bin/bash
# Grade all eval outputs programmatically
set -e

BASE="/Users/jiangqingsong/workspace/devops/devops-skill-workspace/iteration-1"

check() {
  local file="$1" pattern="$2" name="$3" invert="${4:-false}"
  if [ ! -f "$file" ]; then
    echo "FAIL|$name|File not found: $file"
    return
  fi
  if [ "$invert" = "true" ]; then
    if grep -qi "$pattern" "$file" 2>/dev/null; then
      echo "FAIL|$name|Found forbidden pattern: $pattern"
    else
      echo "PASS|$name|No forbidden pattern found"
    fi
  else
    if grep -qi "$pattern" "$file" 2>/dev/null; then
      echo "PASS|$name|Pattern found"
    else
      echo "FAIL|$name|Pattern not found: $pattern"
    fi
  fi
}

grade_eval() {
  local eval_name="$1" variant="$2"
  local dir="$BASE/$eval_name/$variant/outputs"
  echo "=== $eval_name / $variant ==="

  case "$eval_name" in
    eval-init-service)
      # Find deployment.yaml (may be nested)
      deploy=$(find "$dir" -name "deployment.yaml" -type f 2>/dev/null | head -1)
      devops=$(find "$dir" -name ".devops.yaml" -o -name "devops.yaml" | head -1)
      svc=$(find "$dir" -name "service.yaml" -type f 2>/dev/null | head -1)
      prod_kust=$(find "$dir" -path "*/prod/kustomization.yaml" -type f 2>/dev/null | head -1)

      [ -n "$deploy" ] && check "$deploy" "managed-by.*devops-skill\|managed-by: devops-skill" "has-managed-by-label" || echo "FAIL|has-managed-by-label|deployment.yaml not found"
      [ -n "$deploy" ] && check "$deploy" "runAsNonRoot.*true\|runAsNonRoot: true" "has-runAsNonRoot" || echo "FAIL|has-runAsNonRoot|deployment.yaml not found"
      [ -n "$deploy" ] && check "$deploy" "readOnlyRootFilesystem.*true\|readOnlyRootFilesystem: true" "has-readOnlyRootFilesystem" || echo "FAIL|has-readOnlyRootFilesystem|deployment.yaml not found"
      [ -n "$devops" ] && check "$devops" "order-service" "devops-has-service-name" || echo "FAIL|devops-has-service-name|.devops.yaml not found"
      [ -n "$devops" ] && check "$devops" "trade" "devops-has-domain" || echo "FAIL|devops-has-domain|.devops.yaml not found"

      # Check no plaintext secrets
      all_files=$(find "$dir" -name "*.yaml" -o -name "*.yml" 2>/dev/null)
      secret_found=false
      for f in $all_files; do
        if grep -qiE "password:\s*['\"]?[a-zA-Z0-9]" "$f" 2>/dev/null; then
          secret_found=true
          break
        fi
      done
      if [ "$secret_found" = "true" ]; then
        echo "FAIL|no-plaintext-secrets|Found plaintext password in YAML"
      else
        echo "PASS|no-plaintext-secrets|No plaintext passwords found"
      fi
      ;;

    eval-add-dependency)
      redis_instance=$(find "$dir" -name "instance.yaml" -type f 2>/dev/null | head -1)
      devops=$(find "$dir" -name ".devops.yaml" -o -name "devops.yaml" | head -1)
      # Find any overlay kustomization that might have secretRef
      svc_overlays=$(find "$dir" -path "*/order-service/overlays/*/kustomization.yaml" -o -path "*/services/*/kustomization.yaml" 2>/dev/null | head -1)

      [ -n "$redis_instance" ] && check "$redis_instance" "order-service-cache" "redis-instance-name" || echo "FAIL|redis-instance-name|instance.yaml not found"
      [ -n "$redis_instance" ] && check "$redis_instance" "managed-by.*devops-skill\|managed-by: devops-skill" "redis-has-managed-by" || echo "FAIL|redis-has-managed-by|instance.yaml not found"
      [ -n "$redis_instance" ] && check "$redis_instance" "owner.*order-service\|owner: order-service" "redis-has-owner" || echo "FAIL|redis-has-owner|instance.yaml not found"

      # Check secretRef in any overlay
      secret_ref_found=false
      for f in $(find "$dir" -name "kustomization.yaml" 2>/dev/null); do
        if grep -q "order-service-cache-secret" "$f" 2>/dev/null; then
          secret_ref_found=true
          break
        fi
      done
      if [ "$secret_ref_found" = "true" ]; then
        echo "PASS|has-secretRef|Found order-service-cache-secret reference"
      else
        echo "FAIL|has-secretRef|No order-service-cache-secret reference found"
      fi

      [ -n "$devops" ] && check "$devops" "redis" "devops-has-redis-dep" || echo "FAIL|devops-has-redis-dep|.devops.yaml not found"
      [ -n "$devops" ] && check "$devops" "owner" "devops-redis-role-owner" || echo "FAIL|devops-redis-role-owner|.devops.yaml not found"
      ;;

    eval-deploy)
      kust=$(find "$dir" -name "kustomization.yaml" -type f 2>/dev/null | head -1)
      commit=$(find "$dir" -name "commit-message.txt" -type f 2>/dev/null | head -1)
      mr=$(find "$dir" -name "mr-description.md" -type f 2>/dev/null | head -1)

      [ -n "$kust" ] && check "$kust" "v1.2.3" "newTag-is-v123" || echo "FAIL|newTag-is-v123|kustomization.yaml not found"
      [ -n "$commit" ] && check "$commit" "ci:.*update.*order-service.*v1.2.3\|ci: update order-service image to v1.2.3" "commit-msg-format" || echo "FAIL|commit-msg-format|commit-message.txt not found"
      [ -n "$mr" ] && check "$mr" "order-service\|影响\|impact" "mr-has-scope" || echo "FAIL|mr-has-scope|mr-description.md not found"
      ;;
  esac
}

# Grade all
for eval_name in eval-init-service eval-add-dependency eval-deploy; do
  for variant in with_skill without_skill; do
    grade_eval "$eval_name" "$variant"
  done
done
