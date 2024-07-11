export GIT_REPO := https://github.com/JacekZubielik/k3s-homelab-autopilot.git

all:

.PHONY: copy-kubeconfig deploy-longhorn-tags1 deploy-longhorn-tags2 import-sealed-secrets delete-sealed-secrets-key deploy-sops deploy-argocd-autopilot login-argocd password-argocd password-grafana help

deploy-all:copy-kubeconfig deploy-longhorn-tags 

copy-kubeconfig: ## Copy 'kubeconfig'.
	@echo "\nCopy kubeconfig to ~/.kube/ ...\n"
	@scp vagrant@192.168.40.200:~/.kube/config ~/.kube/config
	@kubectl get nodes --show-kind

deploy-longhorn-tags1: ## Create a disk on a specific set of nodes.
	@echo "\nCreate a disk on a specific set of nodes ...\n"
	@kubectl annotate --overwrite node dev-k3s-master-0 node.longhorn.io/default-disks-config='[{"name":"nvme-0","path":"/mnt/nvme-0/PV/longhorn","allowScheduling":false,"storageReserved":10Gi,"tags":["nvme-0","fast"]}]'
	@kubectl annotate --overwrite node dev-k3s-master-0 node.longhorn.io/default-node-tags='["fast","storage"]'
	@echo "\n"
	@kubectl annotate --list nodes dev-k3s-master-0
	@echo "\n"
	@kubectl label --overwrite node dev-k3s-master-0 node.longhorn.io/create-default-disk='config'
	@echo "\n"
	@kubectl label --list nodes dev-k3s-master-0
	@echo "\n"
	# @kubectl label --overwrite node dev-k3s-master-0 storage=longhorn
	# @kubectl label --overwrite node dev-k3s-master-0 node.longhorn.io/create-default-disk='true'

deploy-longhorn-tags2: ## Create a disk on a specific set of nodes.
	@echo "\nCreate a disk on a specific set of nodes ...\n"
	@kubectl annotate --overwrite node dev-k3s-master-0 node.longhorn.io/default-disks-config='{"name":"nvme-0","path":"/mnt/nvme-0/PV/longhorn","allowScheduling":false,"storageReserved":10Gi,"tags":["nvme-0","fast"]}'
	@kubectl annotate --overwrite node dev-k3s-master-0 node.longhorn.io/default-node-tags='["fast","storage"]'
	@echo "\n"
	@kubectl annotate --list nodes dev-k3s-master-0
	@echo "\n"
	@kubectl label --overwrite node dev-k3s-master-0 node.longhorn.io/create-default-disk='config'
	@echo "\n"
	@kubectl label --list nodes dev-k3s-master-0
	@echo "\n"

import-sealed-secrets: ## Import secrets and restart sealed-secrets pod.
	@echo "\nImport secrets and restart sealed-secrets pod ...\n"
	@kubectl create namespace sealed-secrets --dry-run=client --output=yaml \
			| kubectl apply -f -
	@kubectl apply -f sealed-secrets-keytlh79.key
	@kubectl delete pod -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets

delete-sealed-secrets-key: ## Delete sealed-secrets key.
	@echo "\nDelete sealed-secrets key ...\n"
	@kubectl delete secret -n sealed-secrets sealed-secrets-keytlh79

import-sops: ## Import a sops AGE and PGP secret keys.
	@echo "\nImport a sops AGE and PGP secret keys ...\n"
	@kubectl create namespace argocd --dry-run=client --output=yaml \
			| kubectl apply -f -
	@cat ~/.config/sops/age/keys.txt | kubectl create secret generic sops-age --namespace=argocd --from-file=keys.txt=/dev/stdin
	@gpg --export-secret-keys --armor "${SOPS_PGP_FP}" | kubectl create secret generic sops-gpg --namespace=argocd --from-file=sops.asc=/dev/stdin

deploy-argocd-autopilot: ## Deploy Argo CD autopilot recovery on Kubernetes cluster.
	@echo "\nDeploy Argo CD autopilot on Kubernetes cluster ...\n"
	@argocd-autopilot repo bootstrap --recover --app "${GIT_REPO}/bootstrap/argo-cd"
	@kubectl -n argocd wait --for=condition=available --timeout=600s --all deployments

login-argocd: ## Login to ArgoCD CLI.
	@echo "\nLogin to ArgoCD CLI ...\n"
	@argocd login 192.168.40.182 --insecure --username admin --password $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

password-argocd: ## Show admin password for ArgoCD.
	@echo "\nAdmin password for ArgoCD:\n"
	@kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

password-grafana: ## Show admin password for Grafana.
	@echo "\nAdmin password for Grafana:\n"
	@kubectl get secrets -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d

help: ## Display this help.
	@echo "\nDisplay this help ..."
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
