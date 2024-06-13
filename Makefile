export GIT_REPO := https://github.com/JacekZubielik/k3s-homelab-autopilot.git

all: help

.PHONY: copy-kubeconfig
copy-kubeconfig:
	@scp vagrant@192.168.40.119:~/.kube/config ~/.kube/config

.PHONY: argocd-namespace
argocd-namespace:
	@kubectl create namespace argocd --dry-run=client --output=yaml \
			| kubectl apply -f -

.PHONY: import-sealed-secrets
import-sealed-secrets:
	@kubectl apply -f sealed-secrets-keytlh79.key

.PHONY: restart-sealed-secrets
restart-sealed-secrets:
	@kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets

.PHONY: deploy-sops-age
deploy-sops-age: ## Deploy a sops-age secret
	@cat ~/.config/sops/age/keys.txt | kubectl create secret generic sops-age --namespace=argocd --from-file=keys.txt=/dev/stdin

.PHONY: deploy-sops-gpg
deploy-sops-gpg: ## Deploy a sops-gpg secret
	@gpg --export-secret-keys --armor "${SOPS_PGP_FP}" | kubectl create secret generic sops-gpg --namespace=argocd --from-file=sops.asc=/dev/stdin

.PHONY: deploy-argocd-autopilot-recovery
deploy-argocd-autopilot-recovery: ## Deploy Argo CD autopilot on Kubernetes cluster
	argocd-autopilot repo bootstrap --recover --app "${GIT_REPO}/bootstrap/argo-cd"
	@kubectl -n argocd wait --for=condition=available --timeout=300s --all deployments

.PHONY: login-argocd
login-argocd:
	@kubectl port-forward service/argocd-server -n argocd 8080:443 &          
	argocd login localhost:8080 --insecure --username admin --password $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

.PHONY: argocd-password
argocd-password: ## Show admin password for ArgoCD
	@kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

.PHONY: grafana-password
grafana-password: ## Show admin password for Grafana
	@kubectl get secrets -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
