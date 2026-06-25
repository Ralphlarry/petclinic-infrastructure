SHELL := /bin/bash

BOOTSTRAP_DIR ?= terraform/bootstrap
PROD_DIR      ?= terraform/environments/prod
APP_REPO      ?= ../spring-petclinic-microservices
export PROD_DIR APP_REPO

.PHONY: help state platform kubeconfig addons up down plan fmt

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

state: ## One-time: create the S3 state bucket + DynamoDB lock table
	terraform -chdir=$(BOOTSTRAP_DIR) init
	terraform -chdir=$(BOOTSTRAP_DIR) apply

plan: ## Plan the AWS platform
	terraform -chdir=$(PROD_DIR) init
	terraform -chdir=$(PROD_DIR) plan

platform: ## terraform apply the AWS platform (VPC/EKS/ECR/IAM/Karpenter IAM)
	terraform -chdir=$(PROD_DIR) init
	terraform -chdir=$(PROD_DIR) apply

kubeconfig: ## Point kubectl at the cluster
	aws eks update-kubeconfig \
	  --name $$(terraform -chdir=$(PROD_DIR) output -raw cluster_name) \
	  --region $$(terraform -chdir=$(PROD_DIR) output -raw aws_region)

addons: ## Install LB controller, metrics-server, Karpenter, Argo CD + the app
	bash scripts/addons.sh

up: platform addons ## Full bring-up (run `make state` once first, on a brand-new account)
	@echo "Platform + add-ons up. If ECR was empty (fresh build), trigger CI to push images."

down: ## Ordered teardown (k8s layer first, with waits) then terraform destroy
	bash scripts/teardown.sh

fmt: ## terraform fmt
	terraform -chdir=$(PROD_DIR) fmt -recursive ../..
