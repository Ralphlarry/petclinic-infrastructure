# Bootstrap & teardown — reproducible cluster lifecycle

Brings the whole platform up and tears it down **in the correct order**, so you
can destroy the cluster to save cost and rebuild it for a demo without orphaning
AWS resources (the classic "VPC won't delete because of a leftover ALB / ENIs"
trap).

## Why this exists (the important bit)
Terraform manages the AWS platform (VPC, EKS, ECR, IAM, Karpenter IAM/SQS). It does
**not** manage the things installed on top with Helm/kubectl (the AWS Load Balancer
Controller, metrics-server, Karpenter's controller, Argo CD, the app), nor the
**ALB and EC2 nodes those controllers create at runtime**. A naive `terraform
destroy` leaves those behind and then hangs deleting the VPC. So teardown must
remove the Kubernetes layer first, wait for the async cleanup, and only then run
`terraform destroy`. That ordering is what `make down` encodes.

## Prerequisites
`terraform` ≥ 1.5, `awscli` v2 (logged in), `kubectl`, `helm`, and `make`.
Run from the **infra repo root**. The scripts expect the app repo checked out as a
sibling at `../spring-petclinic-microservices` (override with `APP_REPO=...`).

## Bring up
```bash
make state       # ONCE per account — creates the S3 state bucket + DynamoDB lock
make up          # = platform (terraform apply) + addons (helm/kubectl, ordered)
```
`make up` runs:
1. `terraform apply` → VPC, EKS, ECR, IAM, Karpenter IAM + SQS.
2. `scripts/addons.sh` → AWS LB Controller → metrics-server → Karpenter (CRDs +
   controller) → NodePool/EC2NodeClass → Argo CD → the petclinic Application.

> **Fresh build caveat:** a brand-new platform has an **empty ECR**, so the app
> pods will `ImagePullBackOff` until images exist. Trigger CI to populate it —
> push a commit to the app repo's `main`, or:
> ```bash
> gh workflow run "Build and Deploy Petclinic (GitOps)" -R Ralphlarry/spring-petclinic-microservices
> ```
> Argo CD syncs automatically once images are in ECR.

> **DNS caveat:** the rebuilt ingress provisions a **new** ALB with a new hostname.
> Update your `petclinic.ralphnetwork.online` record to point at the new ALB
> (`kubectl get ingress -n petclinic` shows the address).

## Tear down
```bash
make down
```
`scripts/teardown.sh` runs, in order, with waits:
1. Delete the Argo CD Application → cascade-deletes the app + ingress → LB
   controller removes the ALB. **Waits** until the ingress/ALB is gone.
2. Delete the Karpenter NodePool/EC2NodeClass → Karpenter drains its nodes.
   **Waits** until no nodeclaims remain.
3. Delete any leftover LoadBalancer Services (safety).
4. `helm uninstall` the add-ons.
5. `terraform destroy` the platform.

The remote-state backend (`terraform/bootstrap`) is intentionally left intact —
don't destroy it unless you're abandoning the project.

## Useful overrides
```bash
make up APP_REPO=/path/to/app/checkout
make addons KARPENTER_VERSION=1.13.0 ARGOCD_VERSION=9.7.0
make down            # uses the same defaults
```

## Targets
`make help` lists them: `state`, `plan`, `platform`, `kubeconfig`, `addons`,
`up`, `down`, `fmt`.

## What's still manual (by design)
- **ACM certificate + base DNS zone** — created once, outlive teardowns; only the
  A/ALIAS record value changes per rebuild.
- **ECR image population** — comes from the CI pipeline, not this bootstrap.
