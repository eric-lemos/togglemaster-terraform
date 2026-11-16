#!/usr/bin/env bash
set -euo pipefail

state_resources="$(terraform state list)"
if ! grep -q '^module\.eks\.' <<< "$state_resources"; then
  echo "No EKS resources in the infrastructure state; skipping Helm uninstall."
  exit 0
fi

cluster_name="$(terraform output -raw eks_cluster_name)"
if [[ -z "$cluster_name" ]]; then
  echo "EKS resources exist in state, but eks_cluster_name is empty." >&2
  exit 1
fi
aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" >/dev/null
aws eks update-kubeconfig --name "$cluster_name" --region "$AWS_REGION"

while read -r namespace release; do
  installed="$(helm list --namespace "$namespace" --all --filter "^${release}$" --short)"
  if [[ "$installed" == "$release" ]]; then
    helm uninstall "$release" --namespace "$namespace" --wait --timeout 10m
  elif [[ -n "$installed" ]]; then
    echo "Unexpected Helm list output for $namespace/$release: $installed" >&2
    exit 1
  else
    echo "Release $namespace/$release is already absent."
  fi
done <<'RELEASES'
observability otel-gateway
observability otel-agent
observability loki
observability monitoring
argocd argocd
kube-system metrics-server
ingress-nginx ingress-nginx
RELEASES
