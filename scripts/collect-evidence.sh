#!/usr/bin/env bash
set -Eeuo pipefail

# Collect reproducible, non-secret project verification evidence.
# Run from any directory; output is written under the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$ROOT_DIR/docs/evidence/generated/$TIMESTAMP"
mkdir -p "$OUT_DIR"

SUMMARY="$OUT_DIR/collection-summary.txt"
exec > >(tee -a "$SUMMARY") 2>&1

echo "Production DevSecOps evidence collection"
echo "UTC timestamp: $TIMESTAMP"
echo "Repository: $ROOT_DIR"
echo "Evidence directory: $OUT_DIR"
echo

run_check() {
  local name="$1"
  shift
  local logfile="$OUT_DIR/$name"
  echo "===== $name ====="
  if "$@" >"$logfile" 2>&1; then
    echo "RESULT: PASS"
  else
    local rc=$?
    echo "RESULT: FAIL (exit $rc)"
    echo "See: $logfile"
  fi
  cat "$logfile"
  echo
}

command -v terraform >/dev/null 2>&1 || echo "NOTICE: terraform not installed"
command -v checkov >/dev/null 2>&1 || echo "NOTICE: checkov not installed"
command -v opa >/dev/null 2>&1 || echo "NOTICE: opa not installed"
command -v trivy >/dev/null 2>&1 || echo "NOTICE: trivy not installed"
command -v docker >/dev/null 2>&1 || echo "NOTICE: docker not installed"
command -v az >/dev/null 2>&1 || echo "NOTICE: Azure CLI not installed"

# Application tests and static checks
if command -v python3 >/dev/null 2>&1; then
  if python3 -m pytest --version >/dev/null 2>&1; then
    run_check "pytest.txt" python3 -m pytest -q
  else
    echo "SKIP: pytest is not installed in the active Python environment."
  fi
fi

if command -v ruff >/dev/null 2>&1; then
  run_check "ruff.txt" ruff check app tests
else
  echo "SKIP: ruff is not installed."
fi

if command -v bandit >/dev/null 2>&1; then
  run_check "bandit.txt" bandit -r app -ll
else
  echo "SKIP: bandit is not installed."
fi

if command -v pip-audit >/dev/null 2>&1; then
  run_check "pip-audit.txt" pip-audit -r requirements.txt
else
  echo "SKIP: pip-audit is not installed."
fi

# Terraform checks are run independently in each layer.
if command -v terraform >/dev/null 2>&1; then
  for dir in infra/bootstrap-state infra/foundation infra/terraform; do
    safe_name="${dir//\//-}"
    run_check "$safe_name-fmt.txt" terraform -chdir="$ROOT_DIR/$dir" fmt -check -recursive
    run_check "$safe_name-validate.txt" terraform -chdir="$ROOT_DIR/$dir" init -backend=false -input=false
    run_check "$safe_name-validate-result.txt" terraform -chdir="$ROOT_DIR/$dir" validate -no-color
  done
else
  echo "SKIP: Terraform checks not run; terraform is unavailable."
fi

# Checkov reports in JSON for machine-readable evidence.
if command -v checkov >/dev/null 2>&1; then
  for dir in infra/bootstrap-state infra/foundation infra/terraform; do
    safe_name="${dir//\//-}"
    if [ "$dir" = "infra/bootstrap-state" ]; then
      checkov -d "$dir" --framework terraform \
        --skip-check CKV_AZURE_33,CKV_AZURE_206,CKV_AZURE_36,CKV_AZURE_59,CKV2_AZURE_33,CKV2_AZURE_21,CKV2_AZURE_1 \
        -o json >"$OUT_DIR/$safe_name-checkov.json" 2>"$OUT_DIR/$safe_name-checkov.stderr" || true
    else
      checkov -d "$dir" --framework terraform -o json \
        >"$OUT_DIR/$safe_name-checkov.json" 2>"$OUT_DIR/$safe_name-checkov.stderr" || true
    fi
  done
else
  echo "SKIP: Checkov reports not generated; checkov is unavailable."
fi

# OPA tests: prefer local binary, otherwise use the repository's container image.
if command -v opa >/dev/null 2>&1; then
  run_check "opa-tests.txt" opa test policies -v
elif command -v docker >/dev/null 2>&1; then
  run_check "opa-tests.txt" docker run --rm \
    -v "$ROOT_DIR:/workspace" -w /workspace \
    openpolicyagent/opa:1.10.0 test policies -v
else
  echo "SKIP: OPA tests not run; neither opa nor docker is available."
fi

# Build and scan the same local image tag in a reproducible manner.
IMAGE="production-devsecops-compliance:evidence-$TIMESTAMP"
if command -v docker >/dev/null 2>&1; then
  run_check "docker-build.txt" docker build -t "$IMAGE" .
  if command -v trivy >/dev/null 2>&1; then
    run_check "trivy-image.txt" trivy image --format json --output "$OUT_DIR/trivy-image.json" \
      --severity HIGH,CRITICAL --ignore-unfixed "$IMAGE"
  else
    echo "SKIP: Trivy image scan not run; trivy is unavailable."
  fi
else
  echo "SKIP: Docker build not run; docker is unavailable."
fi

# Capture non-secret Azure resource metadata only. Do not dump account credentials,
# access tokens, Terraform state, environment variables, or secret values.
if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
  az account show --query '{name:name,tenantId:tenantId,state:state}' -o json \
    >"$OUT_DIR/azure-account-context.json" || true
  az resource list \
    --resource-group production-devsecops-compliance-rg \
    --query '[].{name:name,type:type,location:location}' -o json \
    >"$OUT_DIR/azure-resource-inventory.json" || true
  echo "Azure metadata captured (subscription ID and credentials intentionally omitted)."
else
  echo "SKIP: Azure metadata not captured; Azure CLI is unavailable or not authenticated."
fi

cat >"$OUT_DIR/README.txt" <<EOF
Evidence collection: $TIMESTAMP (UTC)

This directory was generated by scripts/collect-evidence.sh.
Review every report and its exit status before publishing it.

Do not commit:
- Terraform state files or plan files
- credentials, tokens, private keys, or .env files
- unredacted logs containing secrets, personal data, or sensitive resource details

A generated report is evidence of the command run at this timestamp only.
It is not an independent security certification or proof of a production deployment.
EOF

echo "===== Collection complete ====="
echo "Evidence saved to: $OUT_DIR"
echo "Review collection-summary.txt and individual reports before sharing."
