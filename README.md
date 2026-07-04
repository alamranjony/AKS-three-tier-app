# Production-Ready Kubernetes Platform on Azure

Two Node.js apps (frontend + backend), containerized, deployed to Azure
Kubernetes Service via an Azure DevOps pipeline, on infrastructure
provisioned by custom Terraform modules.

---

## 1. Prerequisites

| Tool | Why | Install |
|---|---|---|
| Azure subscription | Everything runs on Azure | https://portal.azure.com |
| Azure CLI (`az`) | Manual setup steps, verification | `winget install Microsoft.AzureCLI` / `brew install azure-cli` |
| Docker Desktop | Build/run images locally | https://docs.docker.com/get-docker |
| kubectl | Talk to AKS | `az aks install-cli` |
| Terraform >= 1.6 | Provision infra | https://developer.hashicorp.com/terraform/install |
| Node.js 20.x | Run apps outside Docker if needed | https://nodejs.org |
| Azure DevOps organization + project | Host the pipeline | https://dev.azure.com |
| GitHub (or Azure Repos) account | Source control | — |

Run `az login` once and confirm you're on the right subscription:
```bash
az account show
```

---

## 2. Run it locally first (fast feedback before touching Azure)

```bash
cd devops-assessment
docker compose up -d
curl http://localhost:8080          # -> Application is running
curl http://localhost:8080/health   # -> {"status":"ok"}
curl http://localhost:3000          # -> frontend HTML showing backend health
docker compose down
```

---

## 3. Azure Portal GUI prerequisites (one-time, manual)

These are the pieces Terraform can't create for itself, or that are genuinely
faster/clearer to do once in the Portal than to script.

### 3.1 Create the Terraform remote state storage account
Portal → **Storage accounts** → **+ Create**
- Resource group: create new, name it `tfstate-rg`
- Storage account name: something globally unique, e.g. `tfstatedevopsassess`
  (must match `terraform/provider.tf`'s `backend "azurerm"` block — edit that
  file if you pick a different name)
- Region: same as you'll deploy AKS to (e.g. East US)
- Redundancy: LRS is fine for this exercise
After creation → open the storage account → **Containers** → **+ Container**
→ name it `tfstate`, access level **Private**.

*(Equivalent CLI, if you prefer not to click through the Portal — both are
shown in `terraform/provider.tf` as a comment.)*

### 3.2 Create a Service Principal for Azure DevOps
Portal → **Microsoft Entra ID** → **App registrations** → **+ New registration**
- Name: `devops-assessment-sp`
- Register it, then note the **Application (client) ID** and **Directory
  (tenant) ID** on the overview page.
- **Certificates & secrets** → **+ New client secret** → copy the value
  immediately (shown once).
- Back in the subscription: **Subscriptions** → your subscription →
  **Access control (IAM)** → **+ Add role assignment** → role
  **Contributor** (+ separately **User Access Administrator**, needed
  because Terraform creates the AKS→ACR role assignment) → assign to the
  app registration you just created.

### 3.3 Create the Azure DevOps project and service connections
1. https://dev.azure.com → **+ New project** → name it `devops-assessment`.
2. **Project settings** → **Service connections** → **New service connection**
   → **Azure Resource Manager** → **Service principal (manual)** → paste the
   Subscription ID, Tenant ID, Client ID, and Client secret from step 3.2.
   Name it to match `azureServiceConnection` used in `azure-pipelines.yml`.
3. After the Terraform stage creates the ACR (or if you create it manually
   first), add a second service connection: **Docker Registry** → **Azure
   Container Registry** → select the registry → name it to match
   `acrServiceConnection`.
4. **Pipelines** → **Library** → **+ Variable group** → create one holding:
   `azureServiceConnection`, `acrServiceConnection`, `acrLoginServer`,
   `aksClusterName`, `aksResourceGroup`, and a **secret** variable
   `dbAdminPassword`. Link this variable group in the pipeline (or paste
   values as pipeline variables directly).
5. **Pipelines** → **Environments** → **+ New environment** → name it
   `production` (matches the `environment: 'production'` in
   `azure-pipelines.yml`) → **Approvals and checks** → add yourself as a
   required approver. This is what creates the production approval gate.
6. **Repos** → push this project's code (or connect an existing GitHub repo
   under **Project settings → GitHub connections** if your source lives on
   GitHub instead of Azure Repos).

### 3.4 Enable the Application Gateway Ingress Controller (AGIC)
The `k8s/ingress.yaml` manifest targets AGIC (`ingressClassName:
azure-application-gateway`) instead of a self-managed nginx-ingress pod,
so Azure's native L7 load balancer configures itself directly from the
Ingress resource.

```bash
# Create an Application Gateway (Standard_v2, in its own subnet in the
# same VNet Terraform created) if you don't already have one:
az network public-ip create -g <rg> -n devops-assessment-agw-pip --sku Standard --allocation-method Static
az network application-gateway create \
  -g <rg> -n devops-assessment-agw \
  --sku Standard_v2 --capacity 2 \
  --vnet-name <vnet-name-from-terraform-output> \
  --subnet <a-dedicated-appgw-subnet> \
  --public-ip-address devops-assessment-agw-pip

# Enable the AGIC add-on on the AKS cluster, pointing at that gateway:
az aks enable-addons \
  --resource-group <aksResourceGroup> \
  --name <aksClusterName> \
  --addons ingress-appgw \
  --appgw-id $(az network application-gateway show -g <rg> -n devops-assessment-agw --query id -o tsv)
```
AGIC then watches for `Ingress` resources cluster-wide and configures the
Application Gateway's listeners/rules/backend pools automatically —
`kubectl apply -f k8s/ingress.yaml` is the only manifest step needed
after this one-time setup.

**Do you need a host (`example.domain.com`), or can you rely on a
default AKS domain?** AKS has no built-in default domain (unlike some
managed load balancers that hand you a free `*.provider.com` DNS name).
Application Gateway just gets a public IP. Three real choices, all
documented inline as commented-out options in `k8s/ingress.yaml`:

1. **No host at all** — reach the app at `http://<appgw-public-ip>/`.
   This is what the manifest uses by default; fine for this assessment.
2. **Free Azure-managed FQDN** — attach a DNS label to the public IP
   Azure already gave you: `az network public-ip update -g <rg> -n
   devops-assessment-agw-pip --dns-name devops-assessment` → you get
   `devops-assessment.<region>.cloudapp.azure.com` at no extra cost, no
   domain purchase required.
3. **Your own custom domain** — point a DNS A record you control at the
   Application Gateway's public IP. Needed for real production use
   (branding, and it's what lets `cert-manager` do automated TLS via
   HTTP-01/DNS-01 challenges).

### 3.5 Create the pipeline
**Pipelines** → **New pipeline** → point it at your repo → **Existing Azure
Pipelines YAML file** → select `/azure-pipelines.yml` → **Save** (don't run
yet until the variable group above is in place).

---

## 4. Provision the infrastructure with Terraform

You can either run Terraform locally first (recommended for the first run,
so you can watch it and catch issues) or trigger it from the pipeline.

### 4.1 Locally
```bash
cd terraform
terraform init
terraform plan -var="db_admin_password=<choose-a-strong-password>" -out=tfplan
terraform apply tfplan
terraform output acr_login_server
terraform output cluster_name
```
Copy those two output values into the Azure DevOps variable group
(`acrLoginServer`, `aksClusterName`) and note the resource group name
(`<project_name>-<environment>-rg`, e.g. `devopsassess-dev-rg`) as
`aksResourceGroup`.

### 4.2 From the pipeline
Run the pipeline manually with the `provisionInfra` parameter set to `true`
(**Run pipeline** → parameters). This runs the `Provision_Infra` stage
(`terraform init/plan/apply`) using the `azureServiceConnection`. Leave it
`false` on ordinary app-code pushes so the pipeline doesn't re-run
`terraform apply` on every commit.

See `terraform/README.md` for the full design explanation: module
breakdown, safe AKS upgrades, node pool resizing, state management,
avoiding downtime, dev/staging/prod separation, secrets handling, and what
to check if Terraform wants to recreate the cluster.

---

## 5. How the apps reach the database privately

The Terraform `database` module deploys an Azure Database for PostgreSQL
**Flexible Server** integrated directly into the VNet's dedicated database
subnet (`delegated_subnet_id`) — this means it never gets a public IP or
public endpoint at all, unlike the (also-private-capable but
public-endpoint-by-default) single-server option.

- **Private DNS**: a Private DNS Zone is created and linked to the VNet
  (`azurerm_private_dns_zone_virtual_network_link`), so pods resolve the
  DB hostname to its private IP automatically — without this link, DNS
  resolution fails even though the network path is open (see
  `docs/troubleshooting.md` Q13).
- **Network isolation**: the AKS subnet and database subnet are separate,
  each with its own NSG. The database subnet's NSG only allows inbound
  TCP 5432 from the AKS subnet's CIDR — nothing else, from anywhere.
- **Only the backend can reach it**: this is enforced at the network layer
  (NSG scoped to the AKS subnet) rather than trusting application code;
  add a Kubernetes `NetworkPolicy` (see `docs/future-improvements.md #8`)
  to restrict it further to just backend pods, not every pod in the subnet.
- **Credentials**: passed to the backend via a Kubernetes Secret
  (`k8s/backend-secret-example.yaml`, example values only — see the
  comments in that file for how it's populated for real). Longer-term, see
  the Key Vault CSI driver proposal in `docs/future-improvements.md #1`.
- **Confirming it's not publicly accessible**: `terraform output
  database_fqdn` resolves only inside the VNet — running `nslookup
  <fqdn>` from outside Azure (e.g. your laptop) will fail to resolve or
  connect, which is the expected/desired result. From the Portal:
  the PostgreSQL Flexible Server's **Networking** blade will show "Private
  access (VNet Integration)" with no public access option enabled.

---

## 6. Deploy both apps via the pipeline

Once the variable group and Terraform outputs are in place:

1. Push to `main` (or run the pipeline manually).
2. **Build_And_Test** stage: installs deps, runs the smoke tests in
   `backend/test.js` / `frontend/test.js`, builds both Docker images, tags
   them with `$(Build.BuildId)`, pushes to ACR.
3. **Release** stage: tags the build as a release.
4. **Deploy** stage: waits for the `production` environment approval (from
   3.3 step 5), substitutes the ACR login server + image tag into the k8s
   manifests, and applies the ConfigMap/Secret/Deployments/Services/Ingress
   to AKS.

### Verify
```bash
az aks get-credentials --resource-group <aksResourceGroup> --name <aksClusterName>
kubectl get pods -o wide
kubectl get svc
kubectl get ingress
```
Backend Service (`backend`) has **no** external IP/Ingress — only
`frontend` is reachable externally, through `k8s/ingress.yaml`.

---

## 7. Security notes

- No secrets, `.tfstate`, or cloud keys are committed — `backend-secret-example.yaml`
  holds placeholders only, and Terraform state lives in the remote Azure
  Storage backend, never in git.
- ACR uses AKS's managed identity (`AcrPull` role assignment in the `aks`
  module) instead of `admin_enabled` credentials or imagePullSecrets.
- The database has no public network path at all (see section 5).

---

# Architecture & Operations Q&A

Below is the explanation how private database connectivity
is designed for an Azure Database (e.g. Azure PostgreSQL Flexible Server)
architecture, and how common Terraform operational questions should be
answered.

---

## Part 1 — Private Database Connectivity

### 1. How does AKS connect privately to the database?

The AKS node pool and the managed database sit inside **the same Virtual
Network (VNet)**, each in its own subnet:

| Subnet          | Example CIDR     | Purpose                          |
|-----------------|------------------|-----------------------------------|
| `aks-subnet`    | `10.0.1.0/24`    | AKS nodes / pods                 |
| `db-subnet`     | `10.0.2.0/24`    | Delegated to the database service|

Traffic from backend pods to the database travels over **private VNet IP
addresses only** — it never touches the public internet, and no public
endpoint is exposed for the database.

### 2. Private subnet or private endpoint design — which pattern, and why?

There are two common patterns for making an Azure PaaS database private:

- **VNet integration / delegated subnet** — the database subnet is
  delegated to the database service (e.g.
  `Microsoft.DBforPostgreSQL/flexibleServers`), and the database gets an IP
  address directly inside that subnet.
  ```hcl
  delegated_subnet_id           = var.database_subnet_id
  public_network_access_enabled = false
  ```
- **Private Endpoint** — a private NIC is injected into a subnet that
  points at the PaaS resource's private link service; the database itself
  can remain in a Microsoft-managed network.

Either pattern removes the public endpoint entirely. Delegated-subnet mode
is simpler for single-VNet designs; Private Endpoint mode is preferred when
the database needs to be reachable from multiple VNets or on-prem via
hub-and-spoke, since a Private Endpoint can be exposed into many VNets
without moving the database itself.

### 3. Why is a Private DNS zone required?

Whichever pattern is used, the database's public FQDN
(e.g. `myserver.postgres.database.azure.com`) must still resolve — but to a
**private** IP instead of a public one. This requires:

```hcl
resource "azurerm_private_dns_zone" "db" {
  name = "privatelink.postgres.database.azure.com" # example zone name
}

resource "azurerm_private_dns_zone_virtual_network_link" "db_link" {
  name                  = "db-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.db.name
  virtual_network_id    = azurerm_virtual_network.main.id
}
```

Without this link, the FQDN either fails to resolve or resolves to a public
IP, even though network connectivity would otherwise work — DNS and
network reachability are two separate problems that must both be solved.

### 4. NSG, firewall, or security group rules

Network Security Groups (NSGs) on each subnet enforce least-privilege
access:

- **Database subnet NSG** — allow inbound only on the database port
  (e.g. TCP `5432` for PostgreSQL) **from the AKS subnet CIDR only**; deny
  everything else, including all internet inbound.
  ```
  Priority 100  Allow  Inbound  TCP 5432  Source: 10.0.1.0/24 (aks-subnet)
  Priority 4096 Deny   Inbound  *         Source: *
  ```
- **AKS subnet NSG** — allow intra-VNet traffic and any explicitly required
  inbound (e.g. 80/443 for a public-facing ingress); deny all other
  internet inbound by default.
- No database-level firewall rules (e.g.
  `azurerm_postgresql_flexible_server_firewall_rule`) should exist at all
  in a fully private design — if any exist, that indicates a public access
  path was opened somewhere.

### 5. How is access restricted to only the backend?

This is enforced primarily at the **network layer**: the database NSG only
permits the database port from the AKS subnet's CIDR block. Any pod
scheduled in that subnet could technically reach the database at the
network level — true pod-to-pod isolation additionally requires a
Kubernetes `NetworkPolicy`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-db
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: ["Egress"]
  egress:
    - to:
        - ipBlock:
            cidr: 10.0.2.0/24   # example db-subnet CIDR
      ports:
        - protocol: TCP
          port: 5432
```

Without this, database access is scoped to "anything in the AKS subnet,"
not "specifically the backend pods" — subnet-level NSGs and pod-level
NetworkPolicies are complementary, not substitutes for each other.

### 6. How are database credentials stored securely?

Credentials should never live in Kubernetes manifests, Helm values, or
Terraform `.tfvars` files in plaintext. A typical secure flow:

1. Store the credential in a secrets manager (e.g. **Azure Key Vault**).
2. Grant the application's Kubernetes ServiceAccount a workload identity
   (e.g. **Azure Workload Identity**) with read access to that secret —
   no static credentials stored anywhere in the cluster.
3. Use the **Secrets Store CSI Driver** to sync the secret from the vault
   into a native Kubernetes Secret, mounted only by the pods that need it:
   ```yaml
   apiVersion: secrets-store.csi.x-k8s.io/v1
   kind: SecretProviderClass
   metadata:
     name: db-secrets-provider
   spec:
     provider: azure
     secretObjects:
       - secretName: backend-db-secret
         type: Opaque
         data:
           - objectName: db-password
             key: DB_PASSWORD
   ```
4. The application consumes the resulting Secret via a normal
   `envFrom`/`secretRef` — it never talks to the vault directly.

**Common anti-pattern to avoid**: committing a Terraform `.tfvars` file
containing the admin password to source control. Marking a Terraform
variable `sensitive = true` only hides it from CLI/plan output — it does
**not** encrypt or protect the file itself on disk or in Git history. Any
such file must be `.gitignore`'d and the value sourced from a pipeline
secret or vault instead.

### 7. How do you confirm the database is not publicly accessible?

```bash
# 1. Confirm public access is disabled at the resource level
az postgres flexible-server show \
  --resource-group <resource-group> --name <server-name> \
  --query "{publicAccess:network.publicNetworkAccess, delegatedSubnet:network.delegatedSubnetResourceId}"
# Expect: publicAccess = "Disabled", delegatedSubnet populated

# 2. Confirm no public firewall rules exist
az postgres flexible-server firewall-rule list \
  --resource-group <resource-group> --name <server-name>
# Expect: empty result

# 3. Attempt to resolve/connect from OUTSIDE the VNet (should fail)
nslookup <server-name>.postgres.database.azure.com
psql "host=<fqdn> port=5432 dbname=<db> user=<user>"
# Expect: resolves to nothing usable / times out — no public reachability

# 4. Confirm it DOES resolve/connect from INSIDE the AKS subnet
kubectl exec -it <backend-pod> -- nslookup <server-name>.postgres.database.azure.com
kubectl exec -it <backend-pod> -- nc -zv <server-name>.postgres.database.azure.com 5432
# Expect: resolves to a private IP (e.g. 10.0.2.x) and connects successfully
```

---

## Part 2 — Terraform Operational Q&A

### 1. How to safely upgrade AKS/EKS

1. Check available upgrade targets first:
   ```bash
   az aks get-upgrades --resource-group <rg> --name <cluster-name>
   ```
2. Upgrade **one minor version at a time** — skipping minor versions is
   generally unsupported and can break compatibility.
3. Pin the target version explicitly in Terraform rather than leaving it
   unset (an unset version can silently track a moving default):
   ```hcl
   resource "azurerm_kubernetes_cluster" "this" {
     kubernetes_version = "1.29.4" # example — pin explicitly
   }
   ```
4. Run `terraform plan` and confirm only the version attribute changes —
   nothing should show as "must be replaced."
5. Apply during a maintenance window, using a surge upgrade setting so
   extra nodes are provisioned before old ones are drained:
   ```hcl
   default_node_pool {
     upgrade_settings {
       max_surge = "33%"
     }
   }
   ```
6. Watch the rollout live (`kubectl get nodes -w`), and validate workload
   health before considering the upgrade complete.
7. Test the same upgrade against a staging cluster before applying to
   production whenever possible.

### 2. How to add or resize node pools

- **Adding a new pool** (e.g. a separate pool for GPU or memory-heavy
  workloads) is a non-disruptive, additive Terraform change:
  ```hcl
  resource "azurerm_kubernetes_cluster_node_pool" "extra" {
    name                  = "workerpool2"
    kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
    vm_size               = "Standard_D4s_v5" # example size
    node_count            = 2
    vnet_subnet_id        = var.aks_subnet_id
  }
  ```
- **Resizing an existing pool's node count** is generally safe and
  non-disruptive if the pool uses cluster autoscaling — Terraform should
  `ignore_changes` on `node_count` so the autoscaler, not Terraform, owns
  scaling:
  ```hcl
  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
  ```
- **Changing `vm_size` on an existing pool is not supported in-place** —
  Azure requires creating a new node pool with the desired size, cordoning
  and draining the old pool's nodes, migrating workloads, then deleting the
  old pool. Never assume changing `vm_size` on an existing
  `azurerm_kubernetes_cluster_node_pool` resource will resize nodes without
  a replacement.

### 3. How to maintain Terraform state

- Always use a **remote backend** with locking — never local `.tfstate`
  files for a shared/team project:
  ```hcl
  terraform {
    backend "azurerm" {
      resource_group_name  = "tfstate-rg"        # example
      storage_account_name = "tfstateuniquename"  # must be globally unique
      container_name       = "tfstate"
      key                  = "project.tfstate"
    }
  }
  ```
- Enable **blob versioning and soft-delete** on the storage account holding
  state, so an accidental `terraform destroy` or corrupted state file can
  be recovered.
- Restrict access to the state storage account via RBAC — state files can
  contain sensitive values in plaintext (e.g. generated passwords), so
  treat access to them like access to secrets.
- Never manually edit `.tfstate` by hand; use `terraform state mv` /
  `terraform state rm` / `terraform import` for any state surgery.
- Run `terraform plan` in CI on every PR (read-only) so drift or unintended
  changes are visible before merge, separate from the `apply` step.

### 4. How to avoid downtime during cluster changes

- Prefer changes that are additive or in-place over anything that forces
  replacement — check the `terraform plan` output for
  `# forces replacement` before applying anything to production.
- For node pool changes, always **add the new pool before removing the
  old one** (surge capacity), and drain gracefully rather than deleting
  nodes with running pods.
- Define `PodDisruptionBudget`s for critical workloads so voluntary
  disruptions (node drains, upgrades) never take all replicas offline at
  once:
  ```yaml
  apiVersion: policy/v1
  kind: PodDisruptionBudget
  metadata:
    name: backend-pdb
  spec:
    minAvailable: 1
    selector:
      matchLabels:
        app: backend
  ```
- Use rolling update strategies with sensible `maxUnavailable`/`maxSurge`
  on Deployments so pods are replaced gradually, not all at once.
- Test disruptive changes (cluster upgrades, node pool VM size changes) in
  a staging environment first.

### 5. How to separate dev, staging, and production

Two common approaches, often combined:

- **Separate Terraform state per environment** — either separate
  workspaces or (more commonly recommended) fully separate root modules /
  state files per environment, each with its own `.tfvars`:
  ```
  environments/
    dev/       terraform.tfvars   (small node sizes, 1 node)
    staging/   terraform.tfvars   (mirrors prod topology, smaller scale)
    prod/      terraform.tfvars   (full size, geo-redundant backups)
  ```
- **Shared modules, environment-specific variables** — keep one set of
  reusable modules (`modules/aks`, `modules/network`, `modules/database`)
  and parameterize per-environment differences (SKU, replica count,
  backup retention) via variables rather than duplicating module code:
  ```hcl
  module "aks" {
    source          = "../../modules/aks"
    environment     = "staging"      # example
    node_min_count  = 1
    node_max_count  = 3
  }
  ```
- Use separate resource groups (and ideally separate subscriptions for
  prod vs. non-prod) so an accidental action in dev can never touch
  production resources, and RBAC can be scoped per environment.
- Require manual approval before any `apply` targeting the production
  state/workspace, while dev/staging can auto-apply on merge.

### 6. How to handle secrets outside Terraform code

- Never hardcode secret values in `.tf` or `.tfvars` files that get
  committed to source control.
- Pass secrets into Terraform via **environment variables**
  (`TF_VAR_db_admin_password`) sourced from a CI/CD pipeline's secret
  store, never from a file in the repo:
  ```bash
  export TF_VAR_db_admin_password="$(SECRET_FROM_PIPELINE)"
  terraform apply
  ```
- For values Terraform needs to *generate* (e.g. an initial admin
  password), consider generating it with the `random_password` resource
  and immediately writing it to a secrets manager, rather than storing it
  in state as the long-term source of truth:
  ```hcl
  resource "random_password" "db_admin" {
    length  = 20
    special = true
  }

  resource "azurerm_key_vault_secret" "db_admin" {
    name         = "db-admin-password"
    value        = random_password.db_admin.result
    key_vault_id = azurerm_key_vault.this.id
  }
  ```
- Mark sensitive variables `sensitive = true` to suppress them from CLI
  output and logs — but treat this as a UX safeguard, not encryption;
  the value still exists in plaintext in the state file, so state file
  access control (see Q3) remains essential.
- After initial provisioning, prefer rotating credentials through the
  secrets manager directly (not through Terraform) and use
  `lifecycle { ignore_changes = [administrator_password] }` on the
  resource so a later `terraform apply` doesn't silently reset a rotated
  password back to an old value.

### 7. What to check if Terraform wants to recreate the cluster

1. Run `terraform plan` and find the exact attribute Terraform marks with
   `# forces replacement` — don't assume, read the specific field.
2. Common AKS attributes that force replacement if changed:
   `resource_group_name`, `location`, `dns_prefix`, node pool `vnet_subnet_id`
   or subnet delegation changes, and certain identity/SKU changes.
3. Check for **manual drift** — did someone change the resource directly
   in the cloud portal? Terraform will try to "fix" that by reconciling
   back to the config, which can look like an unwanted replacement.
4. Check whether the **provider version** was recently bumped — a new
   `azurerm` provider version can change a resource's schema/plan
   behavior even with no config change on your end.
5. Compare the live resource state to the Terraform config field by field:
   ```bash
   terraform state show azurerm_kubernetes_cluster.this
   ```
6. If replacement is unavoidable but must not cause downtime, evaluate
   `create_before_destroy`:
   ```hcl
   lifecycle {
     create_before_destroy = true
   }
   ```
   — noting this isn't always feasible for a cluster resource depending on
   naming/DNS constraints, so a planned migration (new cluster, traffic
   cutover, decommission old) may be the safer real-world path.
7. Never `apply` a plan showing cluster replacement without understanding
   exactly why — treat it as a stop-and-investigate signal, not something
   to push through under deploy-pipeline time pressure.
