#!/usr/bin/env bash

set -Eeuo pipefail

readonly AWS_REGION="${1:-${AWS_REGION:-us-east-1}}"
readonly EKS_CLUSTER_NAME="${2:-${EKS_CLUSTER_NAME:-togglemaster-eks-cluster}}"

checkPrerequisites() {
    if ! command -v aws >/dev/null 2>&1; then
        echo "ERROR: AWS CLI não encontrada." >&2
        return 1
    fi
}

cleanupCluster() {
    local ns svc

    if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        echo "==> Cluster EKS encontrado. Configurando kubeconfig..."
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"

        if command -v kubectl >/dev/null 2>&1; then
            echo "==> Removendo Services do tipo LoadBalancer e Ingresses gerenciados pelo K8s..."

            kubectl get svc --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | while read -r ns svc; do
                if [[ -n "$ns" && -n "$svc" ]]; then
                    echo "--> Deletando LoadBalancer Service: $ns/$svc"
                    kubectl delete svc "$svc" -n "$ns" --ignore-not-found --timeout=60s || true
                fi
            done

            echo "--> Deletando namespaces com recursos de rede..."
            kubectl delete namespace ingress-nginx --ignore-not-found --timeout=60s || true
            kubectl delete namespace argocd --ignore-not-found --timeout=60s || true
            kubectl delete namespace togglemaster --ignore-not-found --timeout=60s || true
            kubectl delete namespace observability --ignore-not-found --timeout=60s || true
        else
            echo "WARN: kubectl não instalado. Tentando limpeza direta via AWS CLI..."
        fi
    else
        echo "==> Cluster EKS $EKS_CLUSTER_NAME não encontrado ou já deletado."
    fi
}

cleanupLoadBalancers() {
    local classic_elbs elb v2_elbs elb_arn

    echo "==> Verificando se restaram Load Balancers (Classic ou ALB/NLB) no ambiente..."
    classic_elbs=$(aws elb describe-load-balancers --region "$AWS_REGION" --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output text 2>/dev/null || true)
    if [[ -n "$classic_elbs" ]]; then
        for elb in $classic_elbs; do
            echo "--> Deletando Classic Load Balancer: $elb"
            aws elb delete-load-balancer --load-balancer-name "$elb" --region "$AWS_REGION" 2>/dev/null || true
        done
    fi

    v2_elbs=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null || true)
    if [[ -n "$v2_elbs" ]]; then
        for elb_arn in $v2_elbs; do
            echo "--> Deletando Application/Network Load Balancer: $elb_arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$elb_arn" --region "$AWS_REGION" 2>/dev/null || true
        done
    fi
}

cleanupEcr() {
    local ecr_repos repo image_ids

    echo "==> Esvaziando imagens de todos os repositórios ECR do projeto..."
    ecr_repos=$(aws ecr describe-repositories --region "$AWS_REGION" --query 'repositories[*].repositoryName' --output text 2>/dev/null || true)
    if [[ -n "$ecr_repos" ]]; then
        for repo in $ecr_repos; do
            if [[ "$repo" == togglemaster/* ]]; then
                echo "--> Removendo imagens do repositório ECR: $repo"
                image_ids=$(aws ecr list-images --repository-name "$repo" --region "$AWS_REGION" --query 'imageIds[*]' --output json 2>/dev/null || true)
                if [[ -n "$image_ids" && "$image_ids" != "[]" && "$image_ids" != "null" ]]; then
                    aws ecr batch-delete-image --repository-name "$repo" --region "$AWS_REGION" --image-ids "$image_ids" >/dev/null 2>&1 || true
                fi
            fi
        done
    fi
}

cleanupNetworkInterfaces() {
    local vpc_id enis eni_id status attach_id

    echo "==> Verificando dependências de rede na VPC (ENIs residuais)..."
    vpc_id=$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:Name,Values=togglemaster-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

    if [[ -n "$vpc_id" && "$vpc_id" != "None" && "$vpc_id" != "null" ]]; then
        echo "--> VPC identificada: $vpc_id"
        enis=$(aws ec2 describe-network-interfaces --region "$AWS_REGION" --filters "Name=vpc-id,Values=$vpc_id" --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Attachment.AttachmentId]' --output text 2>/dev/null || true)

        if [[ -n "$enis" ]]; then
            echo "$enis" | while read -r eni_id status attach_id; do
                if [[ -n "$eni_id" ]]; then
                    if [[ "$status" == "in-use" && -n "$attach_id" && "$attach_id" != "None" && "$attach_id" != "null" ]]; then
                        echo "--> Desanexando ENI: $eni_id (attachment: $attach_id)"
                        aws ec2 detach-network-interface --attachment-id "$attach_id" --force --region "$AWS_REGION" 2>/dev/null || true
                        sleep 2
                    fi
                    echo "--> Excluindo ENI residual: $eni_id"
                    aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$AWS_REGION" 2>/dev/null || true
                fi
            done
        fi
    fi
}

main() {
    echo "==> Verificando cluster EKS: $EKS_CLUSTER_NAME na região $AWS_REGION..."
    checkPrerequisites
    cleanupCluster
    cleanupLoadBalancers
    cleanupEcr
    cleanupNetworkInterfaces
    echo "==> Aguardando 30 segundos para que todos os recursos e interfaces sejam liberados pela AWS..."
    sleep 30
    echo "==> Limpeza de pré-destroy concluída com sucesso!"
}

main "$@"
