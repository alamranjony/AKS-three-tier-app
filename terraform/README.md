# Terraform: AKS Platform Provisioning

Module-based Terraform that provisions everything the platform needs on Azure:
resource group, VNet + subnets, AKS cluster, ACR, a private PostgreSQL
Flexible Server, and a Log Analytics workspace for monitoring. All modules
under `modules/` are custom-written (no third-party registry modules), per
the assessment requirement.

## Design

```
modules/
  network/      VNet, AKS subnet, DB subnet (delegated), NSGs
  acr/          Azure Container Registry
  aks/          AKS cluster + AcrPull role assignment for the kubelet identity
  database/     PostgreSQL Flexible Server, VNet-integrated (no public IP)
  monitoring/   Log Analytics workspace, wired into AKS via oms_agent
```

`main.tf` at the root wires the modules together and passes outputs from
one module into another (e.g. the AKS subnet ID from `network` into `aks`,
the ACR ID from `acr` into `aks` for the pull role assignment).

## Prerequisites

- Azure subscription with Owner or Contributor + User Access Administrator
  (needed for the AKS -> ACR role assignment)
- Azure CLI (`az login`) or a service principal for non-interactive auth
- Terraform >= 1.6
- A pre-created storage account for remote state (see `provider.tf` for the
  one-time `az` commands — Terraform cannot create the backend it depends on)

## Usage

```bash
cd terraform
terraform init
terraform plan -var="db_admin_password=$DB_ADMIN_PASSWORD" -out=tfplan
terraform apply tfplan
```

Never put `db_admin_password` in a `.tfvars` file that gets committed. Pass
it as `TF_VAR_db_admin_password` from a pipeline secret/variable group, or
via `-var` on the command line as shown above.

## How to safely upgrade AKS

1. Check available upgrades: `az aks get-upgrades --resource-group <rg> --name <cluster>`.
2. Bump `kubernetes_version` in `variables.tf` (or override with `-var`) by
   **one minor version at a time** — skipping versions is not supported.
3. `terraform plan` and confirm only the AKS control plane / node pool image
   version is changing, nothing is being replaced.
4. Apply during a maintenance window. The `upgrade_settings.max_surge = "33%"`
   setting on the node pool means AKS creates extra nodes before draining
   old ones, so pods are rescheduled with minimal disruption rather than
   all nodes going down at once.
5. Watch `kubectl get nodes -w` and `kubectl get pods -A` during the upgrade.

## How to add or resize node pools

- To resize the existing pool: change `node_min_count`/`node_max_count`
  (autoscaler handles the rest) or `node_size` for a VM SKU change. Changing
  `vm_size` forces a node pool replacement — add a **new** node pool
  alongside the old one, drain workloads over, then remove the old one,
  rather than doing an in-place SKU change that would cause downtime.
- To add a pool: define a new `azurerm_kubernetes_cluster_node_pool`
  resource in `modules/aks` (separate from `default_node_pool`, which can't
  be deleted without recreating the whole cluster).

## How Terraform state is maintained

State lives in the `azurerm` backend (Azure Storage blob), configured in
`provider.tf`. Azure Storage's blob lease mechanism provides locking
automatically, so two people/pipelines can't `apply` concurrently and
corrupt state. `terraform state list` / `terraform state show` are used to
inspect state without ever hand-editing the state file.

## How to avoid downtime during cluster changes

- Minimum 2 replicas + readiness probes (see `k8s/`) so the Service always
  has at least one healthy backend during a rolling node/pod replacement.
- `PodDisruptionBudget` (recommended addition — see
  `docs/future-improvements.md`) to stop the node upgrade from draining all
  replicas of a Deployment at once.
- Node pool `max_surge` (see above) so new nodes are ready before old ones
  are cordoned/drained.

## How to separate dev, staging, and production

Use one Terraform **state file per environment**, not one state file with
conditionals. In practice: a separate `backend` `key` per environment
(e.g. `dev.tfstate`, `staging.tfstate`, `prod.tfstate`) and a `*.tfvars`
file per environment (`dev.tfvars`, `prod.tfvars`) setting `environment`,
`node_size`, `node_count`, etc. Run `terraform init -backend-config=...`
and `terraform apply -var-file=dev.tfvars` per environment. This keeps a
mistake in dev's plan from ever being able to touch prod's state.

## How to handle secrets outside Terraform code

- `db_admin_password` is marked `sensitive = true` and is never given a
  default — it must come from an external source (pipeline secret /
  Azure Key Vault) via `TF_VAR_...` at apply time.
- Longer-term, the actual DB credentials the **application** uses should
  live in Azure Key Vault, not in Terraform state at all, with Kubernetes
  pulling them at runtime via the Key Vault CSI driver (see
  `docs/future-improvements.md`).

## What to check if `terraform plan` wants to recreate the cluster

This almost always means a change to an **immutable** AKS attribute, most
commonly:

- `dns_prefix`, `location`, or the subnet a node pool is attached to
- Switching `network_plugin` or `network_policy` after creation
- Changing the default node pool's `vm_size` (forces replacement — see
  node pool section above for the safe way to do this instead)

Run `terraform plan` and read the `-/+` line carefully — it names the exact
attribute forcing replacement. If it's not something intentionally changed,
it's often a drift issue (someone changed the resource in the Azure Portal
directly) — run `terraform plan` again after reconciling, or `terraform
import`/`terraform state show` to confirm what Azure actually has versus
what's in state.
