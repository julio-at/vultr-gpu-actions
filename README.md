# Vultr GPU via GitHub Actions

Ready‑to‑use workflows to **create / inspect / destroy** GPU instances on Vultr using `vultr-cli`.

## Requirements

1. A **Vultr** account with the API enabled.
2. Create a **Personal Access Token** in Vultr and add it to this repo as a **secret**:
   - Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
   - Secret name: **`VULTR_API_KEY`**
3. Nothing else. The workflows install `vultr-cli` automatically.

> **Note:** GPU availability and plan/OS IDs vary by region. Use the **GPU • Inspect & Helpers** workflow or your local CLI to discover them.

## Discover IDs (regions / plans / OS)

- In GitHub: go to **Actions → GPU • Inspect & Helpers → Run workflow**.  
  The Job Summary will show tables for regions, OS, and plans (GPU filtered when possible).

- Locally (optional):
  ```bash
  export VULTR_API_KEY=... # your token
  vultr-cli regions list
  vultr-cli os list
  vultr-cli plans list | grep -i gpu
  ```

## Create a GPU instance

1. Go to **Actions → GPU • Create instance → Run workflow**.
2. Fill in:
   - `region_id` (e.g., `ewr`, `sjc`, `ams`, `fra`, etc.)
   - `plan_id` (e.g., `vcg-1c-16gb-l40s` or another GPU-capable plan in your region)
   - `os_id` (e.g., `215` for Ubuntu 22.04, `477` for Ubuntu 24.04 — verify via `os list`)
   - `label` (optional)
   - `add_ssh_key_ids` (optional, comma-separated Vultr SSH Key IDs)
3. Run the workflow. When it completes:
   - The **Job Summary** shows the **Instance ID**.
   - In **Artifacts**, download `instance-<ID>.json` with details such as IP and status.

## Destroy the instance

1. Copy the **Instance ID** from the create run (or from Inspect).
2. Go to **Actions → GPU • Destroy instance → Run workflow**.
3. Paste the `instance_id` and run.
4. Check the **Job Summary** to confirm deletion.

## SSH and access

- If you passed `add_ssh_key_ids`, those keys are authorized on the server.
- The public IP is printed inside the artifact `instance-<ID>.json` (field `main_ip`).
- Example:
  ```bash
  ssh root@<MAIN_IP>
  ```
  (Change `root` if your chosen OS uses a different default user.)

## Costs & cleanup

- **Shut down / destroy** GPU instances when you are done to avoid charges.
- Use the **Destroy** workflow right after your tests if you don’t need it running.

## Troubleshooting

- **Missing `VULTR_API_KEY`**: add the secret to the repo (name: `VULTR_API_KEY`).
- **Invalid plan/region/OS**: confirm via **GPU • Inspect & Helpers**.
- **No IP assigned** after creation: the script waits up to ~10 minutes. If none appears, check quota/availability.
- **SSH fails**: verify you added correct `SSH Key IDs` and that the OS allows your user to log in.

## Extensions (ideas)

- Save `INSTANCE_ID` as an artifact + auto‑destroy at the end of a test job.
- Labeling and **lifecycle** by branch (e.g., label with `<repo>-<branch>-<run-id>`).
- Terraform + Actions if you prefer declarative IaC.

---

**Done!** With these workflows you can spin up and tear down Vultr GPU instances from GitHub Actions in minutes.
