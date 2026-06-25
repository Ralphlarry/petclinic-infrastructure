#!/usr/bin/env bash
# Install the cluster add-ons + GitOps layer on top of the Terraform platform.
# Order matters: each step waits for the previous before continuing.
set -euo pipefail

PROD_DIR="${PROD_DIR:-terraform/environments/prod}"
APP_REPO="${APP_REPO:-../spring-petclinic-microservices}"   # sibling checkout of the app repo
KARPENTER_VERSION="${KARPENTER_VERSION:-1.13.0}"
ARGOCD_VERSION="${ARGOCD_VERSION:-9.7.0}"
# LB controller chart: leave empty for latest, or pin e.g. LBC_VERSION=1.8.1
LBC_VERSION="${LBC_VERSION:-}"

tfout() { terraform -chdir="$PROD_DIR" output -raw "$1"; }

CLUSTER="$(tfout cluster_name)"
REGION="$(tfout aws_region)"
VPC_ID="$(tfout vpc_id)"
ALB_ROLE_ARN="$(tfout alb_controller_role_arn)"
KARPENTER_QUEUE="$(tfout karpenter_queue_name)"

echo ">> kubeconfig for ${CLUSTER}"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

echo ">> AWS Load Balancer Controller"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system ${LBC_VERSION:+--version "$LBC_VERSION"} \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ALB_ROLE_ARN" \
  --wait

echo ">> metrics-server"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --wait

echo ">> Karpenter (CRDs + controller ${KARPENTER_VERSION})"
helm upgrade --install karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd \
  --version "$KARPENTER_VERSION" -n kube-system --wait
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "$KARPENTER_VERSION" -n kube-system \
  --set settings.clusterName="$CLUSTER" \
  --set settings.interruptionQueue="$KARPENTER_QUEUE" \
  --wait

echo ">> Karpenter NodePool + EC2NodeClass"
kubectl apply -f "$APP_REPO/karpenter/ec2nodeclass.yaml"
kubectl apply -f "$APP_REPO/karpenter/nodepool.yaml"

echo ">> Argo CD (${ARGOCD_VERSION})"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --version "$ARGOCD_VERSION" -n argocd --create-namespace \
  -f "$APP_REPO/argocd/values.yaml" --wait
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo ">> Argo CD Application (petclinic) — GitOps takes over from here"
kubectl apply -f "$APP_REPO/helm/argocd-application.yaml" -n argocd

cat <<EOF

============================================================
 Add-ons installed. Argo CD will now sync the app from git.

 IMPORTANT: on a FRESH platform, ECR is empty, so app pods
 will ImagePullBackOff until images exist. Trigger the CI
 pipeline to populate ECR:
   - push any commit to the app repo's main branch, or
   - gh workflow run "Build and Deploy Petclinic (GitOps)" -R Ralphlarry/spring-petclinic-microservices

 Argo CD admin password:
EOF
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "(secret already rotated/removed)"
echo
echo "============================================================"
