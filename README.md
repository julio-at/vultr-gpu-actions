# Vultr GPU via GitHub Actions (API-based)

Workflows and scripts to **create / inspect / destroy** GPU instances on Vultr. Creation & deletion use the **Vultr REST API** (avoids brittle CLI flags). The helper workflow can use `vultr-cli` to show **GPU plan availability** by region.

---

## Requirements

1. A **Vultr** account with the API enabled.
2. Create a **Personal Access Token** and add it to this repo as a secret:
   - Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
   - Name: **`VULTR_API_KEY`**
3. That’s it. The workflows install what they need (`jq` and, for helpers, `vultr-cli`).

---

## Repository layout

```
.github/workflows/
  gpu-create.yml
  gpu-destroy.yml
  gpu-inspect.yml
scripts/
  create_gpu.sh
  destroy_gpu.sh
  list_helpers.sh
.env.example
README.md
```

- **`create_gpu.sh`** (API) — creates an instance and waits until it has a public IP.
- **`destroy_gpu.sh`** (API) — destroys an instance by ID.
- **`list_helpers.sh`** — prints regions, OS IDs, and **GPU-capable plans available** in a region via `vultr-cli regions availability <region> --type gpu`.

---

## Discover IDs (regions / GPU plans / OS)

### In GitHub (recommended)
Go to **Actions → GPU • Inspect & Helpers → Run workflow** and set the region (default: `ewr`). The **Job Summary** shows:
- Supported **regions**
- Common **OS IDs** (e.g., **215** = Ubuntu 22.04, **477** = Ubuntu 24.04 — confirm in the output)
- **GPU-capable Plan IDs** available in your region (from `regions availability --type gpu`)

### Locally (optional)
```bash
export VULTR_API_KEY=...   # your token
vultr-cli regions list
vultr-cli os list | head -n 50
# Replacement requested (previously there was a grep):
vultr-cli plans list
vultr-cli regions availability $REGION
# To limit to GPU only in a region, you can also:
vultr-cli regions availability $REGION --type gpu
```
> **TIP:** The **Plan ID** is the value you will pass to the create workflow.

---

## Smoke Test Runbook (GitHub Actions)

### 0) Prerequisites (one time)
- Repo secret **`VULTR_API_KEY`** created.
- Workflows and scripts committed to the repo.

### 1) (Optional) Add a test public key
Add `keys/id_ed25519.pub` to the repo (temporary test key). This avoids quoting/escaping issues.

### 2) Get valid IDs with the helper workflow
1. **Actions → GPU • Inspect & Helpers → Run workflow**.  
2. Choose `region_id` (e.g., `ewr`).  
3. Copy one **Plan ID** listed for that region and an **OS ID** (e.g., 477).

### 3) Create the GPU instance
1. **Actions → GPU • Create instance → Run workflow**.  
2. Inputs:
   - `region_id`: `ewr` (or the region you inspected)
   - `plan_id`: `<Plan ID you copied>`
   - `os_id`: `477` (Ubuntu 24.04) or `215` (Ubuntu 22.04)
   - `label`: `smoke-gpu`
   - `add_ssh_key_ids`: *(optional)* `ssh-aaaa,ssh-bbbb`
   - `ssh_public_key`: *(optional)* paste your `.pub` content
   - `ssh_public_key_file`: *(optional, preferred)* `keys/id_ed25519.pub`
3. When it finishes:
   - The **Job Summary** shows the **Instance ID**.
   - In **Artifacts**, download `instance-<ID>.json` (see `main_ip`).

### 4) Verify access (SSH)
Try both users (depends on the image):
```bash
ssh ubuntu@<MAIN_IP>
ssh root@<MAIN_IP>
```

### 5) Destroy the instance (cost cleanup)
1. Copy the **Instance ID**.  
2. **Actions → GPU • Destroy instance → Run workflow**.  
3. Enter `instance_id` and run.

> 💸 **Cost:** GPU instances bill immediately. Destroy when you’re done.

---

## Create / Destroy **locally** (optional)

```bash
export VULTR_API_KEY="<your_token>"

# Discover (defaults to ewr; or pass another region)
./scripts/list_helpers.sh
# or: ./scripts/list_helpers.sh fra

# Create (examples)
./scripts/create_gpu.sh --region ewr --plan <PLAN_ID> --os 477 --label test   --sshkeys "ssh-aaaaaaaa"
# or with a .pub file:
./scripts/create_gpu.sh --region ewr --plan <PLAN_ID> --os 477 --label test   --sshpubfile ~/.ssh/id_ed25519.pub

# Destroy
./scripts/destroy_gpu.sh <INSTANCE_ID>
```

**Billing warning:** Destroy the instance after your tests.

---

## SSH and access

- Try both:
  ```bash
  ssh ubuntu@<IP>
  ssh root@<IP>
  ```
- If login fails, check on the VM:
  ```bash
  sudo cloud-init status --long
  sudo grep -iE 'ssh|authorized_key' /var/log/cloud-init*.log
  ls -la /root/.ssh/ /home/ubuntu/.ssh/ 2>/dev/null
  ```

---

## Quick Troubleshooting

- **Missing `VULTR_API_KEY`** → create the secret.
- **Invalid plan/region/OS** → re-run **Inspect & Helpers** and copy a Plan ID listed for your region.
- **SSH key not injected** → use `ssh_public_key` or `ssh_public_key_file` (cloud-init writes to both `root` and `ubuntu`). You can also pass Vultr **SSH Key IDs** via `add_ssh_key_ids`.
- **No public IP after create** → the script waits ~10 min. If none appears, check capacity/quotas or try another region/plan.

---

## Extensions

- Save `INSTANCE_ID` and auto-destroy at the end of the workflow.
- Labels per run (`smoke-${{ github.run_id }}`) for traceability.
- A post-create verification step (ping/SSH).

---

**Done.** With these workflows and scripts you can spin up and tear down Vultr GPU instances from GitHub Actions or locally, with robust SSH key injection.
