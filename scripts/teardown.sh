#!/usr/bin/env bash
# Ordered teardown. Removes the Kubernetes layer FIRST (so the ALB and Karpenter
# nodes are cleaned up by their controllers), waits for the async deletes, THEN
# runs terraform destroy. This is what prevents the classic "VPC won't delete /
# orphaned load balancer + ENIs" failure.
set -euo pipefail

PROD_DIR="${PROD_DIR:-terraform/environments/prod}"
APP_REPO="${APP_REPO:-../spring-petclinic-microservices}"

wait_gone() {  # wait_gone "<description>" "<command that prints rows while resource exists>"
  local desc="$1"; shift
  echo "   waiting for ${desc} to clear..."
  for _ in $(seq 1 60); do            # up to 10 min
    if ! eval "$*" 2>/dev/null | grep -q .; then echo "   ${desc} clear."; return 0; fi
    sleep 10
  done
  echo "   WARNING: ${desc} still present after timeout — check manually before continuing."
}

echo ">> 1/5 Delete Argo CD Application (cascade-deletes the app + ingress -> removes the ALB)"
kubectl delete -f "$APP_REPO/helm/argocd-application.yaml" -n argocd --ignore-not-found --wait=true || true
# The ingress carries the LB controller finalizer, so it only disappears once the ALB is gone:
wait_gone "petclinic ingress/ALB" "kubectl get ingress -n petclinic 2>/dev/null | grep petclinic"

echo ">> 2/5 Delete Karpenter NodePool/EC2NodeClass (Karpenter drains + terminates its nodes)"
kubectl delete -f "$APP_REPO/karpenter/nodepool.yaml" --ignore-not-found || true
kubectl delete -f "$APP_REPO/karpenter/ec2nodeclass.yaml" --ignore-not-found || true
wait_gone "Karpenter nodeclaims" "kubectl get nodeclaims 2>/dev/null | grep -v NAME"

echo ">> 3/5 Safety: delete any leftover LoadBalancer-type Services in petclinic"
kubectl delete svc -n petclinic --field-selector spec.type=LoadBalancer --ignore-not-found || true

echo ">> 4/5 Uninstall helm add-ons"
helm uninstall argocd -n argocd 2>/dev/null || true
helm uninstall karpenter -n kube-system 2>/dev/null || true
helm uninstall karpenter-crd -n kube-system 2>/dev/null || true
helm uninstall metrics-server -n kube-system 2>/dev/null || true
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

echo ">> 5/5 terraform destroy (AWS platform)"
terraform -chdir="$PROD_DIR" destroy

cat <<'EOF'

============================================================
 Platform destroyed. The remote-state backend (S3 bucket +
 DynamoDB lock table in terraform/bootstrap) was left intact
 on purpose — do NOT destroy it unless you're abandoning the
 project, or you'll lose the ability to manage state.

 Sanity check for leaks (should return nothing petclinic-related):
   aws elbv2 describe-load-balancers --region <region> --query "LoadBalancers[].LoadBalancerName"
   aws ec2 describe-instances --region <region> --filters "Name=tag:karpenter.sh/nodepool,Values=default" --query "Reservations[].Instances[].InstanceId"
============================================================
EOF
