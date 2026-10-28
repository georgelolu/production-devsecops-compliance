#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing ${ENV_FILE}. Copy .env.example to .env first." >&2
  return 1 2>/dev/null || exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${AZURE_SUBSCRIPTION_ID:?Missing AZURE_SUBSCRIPTION_ID in .env}"
: "${AZURE_LOCATION:?Missing AZURE_LOCATION in .env}"
: "${PROJECT_RESOURCE_GROUP:?Missing PROJECT_RESOURCE_GROUP in .env}"

export ARM_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export TF_VAR_location="${AZURE_LOCATION}"
export TF_VAR_resource_group_name="${PROJECT_RESOURCE_GROUP}"

echo "Project environment loaded."
echo "Azure location: ${AZURE_LOCATION}"
echo "Project resource group: ${PROJECT_RESOURCE_GROUP}"
