# k8s-test-runner

> A distributed test execution platform that runs Playwright tests as Kubernetes Jobs.
> Deployable to local Kind clusters for development and AWS EKS for production scale.

**Status:** Phase 1 — Week 2. Local Kind execution working. Parallelism + S3 results coming in Week 3.

## Quick demo

```bash
make demo
```

This will:
1. Create a Kind cluster (if not running)
2. Build the Playwright runner image
3. Load the image into Kind
4. Apply the K8s Job and stream logs
5. Report pass/fail

## Project structure

- `runner/` — Playwright test runner (Dockerized)
- `k8s/` — Kubernetes manifests
- `scripts/` — shell helpers
- `Makefile` — orchestration

## Roadmap

- [x] Week 1 — Kubernetes ramp-up
- [x] Week 2 — Local Kind execution with single Job
- [ ] Week 3 — Parallel jobs + S3 results aggregation
- [ ] Week 4 — Terraform ramp-up
- [ ] Week 5 — EKS deployment via Terraform + IRSA
- [ ] Week 6-7 — CI/CD + documentation polish

## What this demonstrates

(Filled in fully during Phase 3 — placeholder for now.)

- Kubernetes (Jobs, Services, ConfigMaps)
- Docker (multi-arch buildx for ARM/x86)
- Playwright test automation
- Will extend: AWS EKS, Terraform, S3, IAM/IRSA, GitHub Actions CI