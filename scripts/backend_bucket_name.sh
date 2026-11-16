#!/usr/bin/env bash

set -Eeuo pipefail

readonly AWS_REGION="${1:-${AWS_REGION:-}}"
ACCOUNT_ID=""

checkPrerequisites() {
    if [[ -z "$AWS_REGION" ]]; then
        echo "ERROR: AWS_REGION must be provided." >&2
        return 1
    fi

    if [[ ! "$AWS_REGION" =~ ^[a-z0-9-]+$ ]]; then
        echo "ERROR: AWS_REGION contains unsupported characters." >&2
        return 1
    fi

    command -v aws >/dev/null 2>&1 || {
        echo "ERROR: AWS CLI is required." >&2
        return 1
    }

    ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text || true)}"

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
}

main() {
    checkPrerequisites "$@"
    printf 'togglemaster-tfstate-%s-%s\n' "$ACCOUNT_ID" "$AWS_REGION"
}

main "$@"
