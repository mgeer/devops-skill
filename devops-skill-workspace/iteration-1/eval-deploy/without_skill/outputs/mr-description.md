## Deploy order-service v1.2.3 to test

### Summary

Deploy `order-service` image tag `v1.2.3` to the **test** environment.

### Changes

- Updated `services/trade/order-service/overlays/test/kustomization.yaml`:
  - Changed `images[].newTag` from `"latest"` to `"v1.2.3"`

### Service Info

| Field       | Value                                      |
|-------------|--------------------------------------------|
| Service     | order-service                              |
| Domain      | trade                                      |
| Environment | test                                       |
| Image       | harbor.company.com/trade/order-service     |
| Tag         | v1.2.3                                     |
| Namespace   | trade-test                                 |

### Rollback

To rollback, revert the `newTag` in `services/trade/order-service/overlays/test/kustomization.yaml` to the previous value and merge.

### Checklist

- [ ] Image `harbor.company.com/trade/order-service:v1.2.3` exists in Harbor
- [ ] CI pipeline for v1.2.3 passed
- [ ] ArgoCD sync status verified after merge
