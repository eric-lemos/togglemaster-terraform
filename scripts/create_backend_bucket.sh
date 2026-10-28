#!/usr/bin/env bash

set -Eeuo pipefail

BUCKET_NAME="${1:-${TF_BACKEND_BUCKET:-}}"
readonly AWS_REGION="${2:-${AWS_REGION:-}}"
ACCOUNT_ID=""

checkPrerequisites() {
    [[ -n "$AWS_REGION" ]] || {
        echo "ERROR: AWS_REGION must be provided." >&2
        return 1
    }

    command -v aws >/dev/null 2>&1 || {
        echo "ERROR: AWS CLI is required." >&2
        return 1
    }

    ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" || {
        echo "ERROR: AWS credentials are unavailable or expired." >&2
        return 1
    }

    if [[ ${#ACCOUNT_ID} -ne 12 ]]; then
        echo "ERROR: Could not determine a valid 12-digit AWS account ID." >&2
        return 1
    fi

    case "$ACCOUNT_ID" in
        *[!0123456789]*)
            echo "ERROR: Could not determine a valid 12-digit AWS account ID." >&2
            return 1
            ;;
    esac

    if [[ -z "$BUCKET_NAME" ]]; then
        BUCKET_NAME="$(bash "$(dirname "${BASH_SOURCE[0]}")/backend_bucket_name.sh" \
            "$AWS_REGION" "$ACCOUNT_ID")"
    fi
}

createBucket() {
    if aws s3api head-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --expected-bucket-owner "$ACCOUNT_ID" 2>/dev/null; then
        echo "S3 bucket already exists and is accessible: $BUCKET_NAME"
        return 0
    fi

    echo "Creating S3 bucket for Terraform backend: $BUCKET_NAME"

    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        if aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"; then
            return 0
        fi
    else
        if aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration "LocationConstraint=$AWS_REGION"; then
            return 0
        fi
    fi

    if aws s3api head-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --expected-bucket-owner "$ACCOUNT_ID" 2>/dev/null; then
        echo "S3 bucket was created concurrently and is accessible: $BUCKET_NAME"
        return 0
    fi

    echo "ERROR: Could not create or access $BUCKET_NAME. Check S3 permissions and bucket-name availability." >&2
    return 1
}

configureBucket() {
    local versioning_status
    versioning_status="$(aws s3api get-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --query 'Status' \
        --output text 2>/dev/null || true)"

    if [[ "$versioning_status" == "Enabled" ]]; then
        echo "Versioning is already enabled."
    else
        echo "Enabling versioning..."
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --versioning-configuration Status=Enabled
    fi

    local encryption_algorithm
    encryption_algorithm="$(aws s3api get-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
        --output text 2>/dev/null || true)"

    if [[ "$encryption_algorithm" == "AES256" ]]; then
        echo "Default server-side encryption is already enabled with AES256."
    else
        echo "Enabling default server-side encryption..."
        aws s3api put-bucket-encryption \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    fi

    local public_access_block
    public_access_block="$(aws s3api get-public-access-block \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
        --output text 2>/dev/null || true)"

    if [[ "$public_access_block" == $'True\tTrue\tTrue\tTrue' ]]; then
        echo "Public access is already blocked."
    else
        echo "Blocking public access..."
        aws s3api put-public-access-block \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    fi
}

main() {
    checkPrerequisites
    echo "Using Terraform backend bucket: $BUCKET_NAME"
    createBucket
    configureBucket
    echo "Terraform backend bucket is ready: $BUCKET_NAME ($AWS_REGION)"
}

main "$@"