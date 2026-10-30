# Project Evidence and Verification

This directory explains how to collect, review, and present reproducible evidence for the Production DevSecOps & Compliance-as-Code Pipeline.

## Evidence principles

1. Reproducible: prefer tool output and machine-readable reports.
2. Timestamped: each collection is stored in a UTC timestamp directory.
3. Traceable: associate evidence with the source commit and relevant CI run.
4. Sanitized: never publish credentials, access tokens, private keys, Terraform state, sensitive plans, or unredacted personal information.
5. Honest: distinguish passing checks from skipped checks, and validation from deployment.
6. Reviewed: generated reports are ignored by Git until they have been inspected and sanitized.

## Directory structure

```text
docs/evidence/
├── README.md
└── generated/                 # local output; ignored by Git
    └── YYYYMMDDTHHMMSSZ/
        ├── collection-summary.txt
        ├── pytest.txt
        ├── ruff.txt
        ├── bandit.txt
        ├── pip-audit.txt
        ├── infra-*-fmt.txt
        ├── infra-*-validate-result.txt
        ├── infra-*-checkov.json
        ├── opa-tests.txt
        ├── docker-build.txt
        ├── trivy-image.json
        └── azure-resource-inventory.json
```

Not every report will exist in every run. The collection script skips checks when a required tool is unavailable. A missing report is not a passing result.

## 1. Collect local evidence

From the repository root:

```bash
chmod +x scripts/collect-evidence.sh
./scripts/collect-evidence.sh
```

The script attempts to collect:

- pytest application test results.
- Ruff lint results.
- Bandit static analysis.
- pip-audit dependency audit.
- Terraform formatting, initialization without a remote backend, and validation for all three Terraform layers.
- Checkov JSON reports for bootstrap, foundation, and compliance infrastructure.
- OPA policy unit-test output.
- Docker image build output and Trivy image scan report.
- Limited Azure account context and resource inventory, if Azure CLI is installed and authenticated.

It does not run terraform plan or terraform apply. Terraform is initialized with backend=false for local validation; the script does not intentionally access or modify remote state.

Review the output directory printed by the script:

```bash
find docs/evidence/generated -maxdepth 2 -type f -print
cat docs/evidence/generated/<UTC_TIMESTAMP>/collection-summary.txt
```

Replace the placeholder with the actual timestamp directory. Investigate failures; do not edit reports to make them appear successful.

## 2. Evidence register

| Evidence | Artifact | What it demonstrates |
|---|---|---|
| Application tests | pytest.txt | Test suite result for the collected source |
| Code quality | ruff.txt | Ruff lint result |
| Python SAST | bandit.txt | Bandit findings at configured severity |
| Dependency audit | pip-audit.txt | Known dependency vulnerability audit |
| Terraform formatting | infra-*-fmt.txt | Formatting validation for each layer |
| Terraform validation | infra-*-validate-result.txt | Terraform configuration validation |
| IaC security | infra-*-checkov.json | Checkov pass, fail, and skip results |
| Policy tests | opa-tests.txt | OPA/Rego unit-test output |
| Container build | docker-build.txt | Local image build result |
| Container security | trivy-image.json | Trivy image scan results |
| Azure inventory | azure-resource-inventory.json | Resource names, types, and regions |

## 3. Azure control-plane evidence

Capture sanitized Azure Portal screenshots or CLI output for:

| Control | Evidence to capture | Verification focus |
|---|---|---|
| Storage Account | Networking and configuration | Standard ZRS, TLS 1.2, HTTPS-only, Shared Key disabled, anonymous blob access disabled |
| Storage firewall | Networking page | Default action Deny and restricted workstation IP rule |
| Blob private endpoint | Private endpoint overview | Provisioning state and connection Approved |
| Key Vault | Properties and networking | RBAC, soft delete, purge protection, private endpoint |
| Customer-managed key | Key details | Key name, type, enabled and expiry state; never export key material |
| Managed identity | Identity and role assignment | Identity association and Crypto Service Encryption User assignment |
| Private DNS | Record sets and VNet links | Blob and Key Vault records and completed links |
| Log Analytics | Workspace and diagnostic settings | Workspace exists and Blob/Queue diagnostics target it |

Hide subscription identifiers, tenant information, user principal details, public IP addresses, and other sensitive details when they are not necessary for the portfolio.

### Current-state qualification

At the time this evidence plan was written, the audit evidence Storage Account had public network access enabled temporarily, with a default-deny network rule and a restricted workstation IP allowlist. The private endpoint and private DNS configuration existed, but the workstation was outside the VNet and resolved public DNS addresses. The private runner path and end-to-end private DNS/access verification remained outstanding.

Do not describe the Storage Account as private-only until public network access has actually been disabled and access has been verified from the authorized private network path. The Terraform state backend is a separate Storage Account and must remain reachable to the Terraform runner.

## 4. GitHub Actions evidence

For a workflow run:

1. Open the repository Actions tab.
2. Select Production DevSecOps Compliance CI.
3. Open the run for the commit being documented.
4. Capture the run summary with commit SHA and conclusion.
5. Capture application-security job steps.
6. Capture container build and Trivy scan steps.
7. Capture the Terraform matrix results for bootstrap, foundation, and compliance.
8. Capture the OPA release-policy gate result.

Record the workflow URL, commit SHA, branch, timestamp, and conclusion.

A green workflow means the configured CI checks and release policy passed for that run. It does not prove Azure infrastructure was deployed by CI: the workflow uses terraform init -backend=false and does not run Azure deployment commands.

## 5. Checkov interpretation

Keep the full JSON report. For each Terraform layer and scan timestamp, report the counts exactly as produced:

- Passed checks.
- Failed checks.
- Skipped checks and their rationale.
- Remaining accepted risks or temporary configuration.

Do not combine results from different layers or timestamps unless the calculation and source reports are clear.

The compliance layer previously reported **22 passed, 1 failed, and 4 skipped**. The outstanding failure was CKV_AZURE_59 (Storage Account public network access) while public network access remained temporarily enabled. This is a historical result, not a current scan. Re-run Checkov after configuration changes.

## 6. OPA and Trivy evidence

For OPA, preserve verbose unit-test output and the workflow release-policy decision. Current policy tests cover the all-controls-pass case and denial cases for container scan failure and secret-check failure.

For Trivy, preserve the JSON report and exact image tag or digest. The CI workflow tags its image with the Git commit SHA and fails on configured HIGH/CRITICAL vulnerability or secret findings, while ignoring unfixed vulnerabilities.

## 7. Evidence publication checklist

Before adding selected evidence to Git:

- [ ] Confirm the report came from the intended repository commit.
- [ ] Confirm collection date and time.
- [ ] Review failed and skipped checks.
- [ ] Remove credentials, tokens, private keys, environment values, and sensitive identifiers.
- [ ] Never publish Terraform state or plan files.
- [ ] Never publish raw environment dumps or unredacted debug logs.
- [ ] Keep original reports privately if the public copy is redacted.
- [ ] Add a note explaining the command, result, and what the artifact proves.
- [ ] Re-run checks after remediation; do not alter old reports.

Generated evidence under docs/evidence/generated/ is ignored by Git intentionally. Move only reviewed and sanitized artifacts into a curated directory if you want to publish them.

## 8. Current evidence status

This repository now contains a repeatable evidence collection script and this evidence register. A fresh execution from the workstation has not yet been performed as part of this documentation change. Therefore, this commit does not claim new test, Checkov, Trivy, or Azure inventory results.

## Related documentation

- [Project overview](../../README.md)
- [Azure enterprise security architecture](../architecture/azure-enterprise-security-architecture.md)
- [CI/CD security pipeline architecture](../architecture/cicd-security-pipeline-architecture.md)
- [Evidence collection script](../../scripts/collect-evidence.sh)
