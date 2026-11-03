#!/usr/bin/env bash
# Remove resíduos de rede que impedem a exclusão de subnets e security groups
# depois de uma falha do terraform destroy (ENIs órfãs e SGs k8s-elb-* criados
# pelo cloud-controller do Kubernetes, que não estão no state do Terraform).

set -Euo pipefail

readonly AWS_REGION="${1:-${AWS_REGION:-us-east-1}}"
readonly VPC_NAME="${2:-togglemaster-vpc}"

VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:Name,Values=$VPC_NAME" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
    echo "==> VPC $VPC_NAME não encontrada; nada a limpar."
    exit 0
fi

echo "==> Limpando resíduos na VPC $VPC_ID..."

for attempt in 1 2 3 4 5 6; do
    ENIS=$(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Attachment.AttachmentId]' --output text 2>/dev/null || true)

    [[ -z "$ENIS" ]] && break

    echo "--> Tentativa $attempt: $(wc -l <<< "$ENIS") ENI(s) na VPC"
    while read -r eni_id status attach_id; do
        [[ -z "$eni_id" ]] && continue
        if [[ "$status" == "in-use" && -n "$attach_id" && "$attach_id" != "None" ]]; then
            aws ec2 detach-network-interface --attachment-id "$attach_id" --force --region "$AWS_REGION" 2>/dev/null || true
            sleep 2
        fi
        aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$AWS_REGION" 2>/dev/null \
            && echo "    ENI removida: $eni_id"
    done <<< "$ENIS"
    sleep 10
done

K8S_SGS=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=k8s-elb-*" \
    --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null || true)

ALL_SGS=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null || true)

for target in $K8S_SGS; do
    echo "--> Removendo referências ao SG $target"
    for sg in $ALL_SGS; do
        [[ "$sg" == "$target" ]] && continue
        for direction in ingress egress; do
            if [[ "$direction" == "ingress" ]]; then
                filter="!IsEgress"
            else
                filter="IsEgress"
            fi
            RULES=$(aws ec2 describe-security-group-rules --region "$AWS_REGION" \
                --filters "Name=group-id,Values=$sg" \
                --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='$target' && $filter].SecurityGroupRuleId" \
                --output text 2>/dev/null || true)
            if [[ -n "$RULES" && "$RULES" != "None" ]]; then
                # shellcheck disable=SC2086
                aws ec2 "revoke-security-group-$direction" --region "$AWS_REGION" --group-id "$sg" \
                    --security-group-rule-ids $RULES >/dev/null 2>&1 || true
            fi
        done
    done
    aws ec2 delete-security-group --group-id "$target" --region "$AWS_REGION" 2>/dev/null \
        && echo "    SG removido: $target"
done

echo "==> Dependências restantes na VPC (para diagnóstico):"
aws ec2 describe-network-interfaces --region "$AWS_REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' --output text 2>/dev/null || true

exit 0
