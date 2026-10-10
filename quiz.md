# Quiz: Terraform Multi-Environment

Test what you picked up from the guide. Answers are collapsed — no peeking. 👀

---

### 1. Why are Terraform workspaces a poor fit for long-lived dev/staging/prod environments?

<details>
<summary>Show answer</summary>

Workspaces share one codebase but select the environment via `terraform.workspace`, which invites conditional logic (`count = terraform.workspace == "prod" ? 3 : 1`) scattered through the code. It's also easy to run a command in the wrong workspace and apply dev changes to prod state. They're better for ephemeral copies (PR previews, personal sandboxes); long-lived environments deserve separate, explicit stacks with their own state files.
</details>

---

### 2. What's wrong with this module, and how would you fix it?

```hcl
module "app" {
  source        = "../../modules/compute"
  instance_type = var.env == "prod" ? "m6i.large" : "t3.small"
}
```

<details>
<summary>Show answer</summary>

The environment-conditional leaked into the stack wiring — and if this pattern moves *inside* the module it gets worse. The fix: pass a plain variable and resolve the value outside, e.g. a `local.sizing[var.environment].instance_type` map or a per-environment `*.tfvars` file. Golden rule: **modules hold logic, environments hold configuration.**
</details>

---

### 3. Your teammate ran `terraform apply` on their laptop while CI was applying the same environment. What prevents the state file from corrupting, and what did you forget to configure if it doesn't?

<details>
<summary>Show answer</summary>

**State locking** — with the S3 backend, a DynamoDB table (`dynamodb_table` in the backend block) holds a lock during apply so the second run fails fast instead of writing a torn state. If corruption was possible, you forgot the lock table — S3 alone does not lock. (Also: applies should run from CI on `main`, not from laptops.)
</details>

---

### 4. Staging runs a single `t3.micro` with no backups; prod runs a multi-AZ fleet with 30-day backups. A deploy passes staging but breaks prod. What did staging fail to be, and why does it matter?

<details>
<summary>Show answer</summary>

Staging failed to be **prod-like**. If the environment where you validate releases doesn't resemble prod in topology (AZ count, instance class, multi-AZ, backups), it tests almost nothing — prod becomes the place you discover the bugs. Staging should be a scaled-down but architecturally faithful copy of prod.
</details>

---

### 5. A developer edits a security group directly in the AWS console to fix an incident, then goes home. What's the correct follow-up, and what happens at the next `terraform apply` if you do nothing?

<details>
<summary>Show answer</summary>

The correct follow-up: **encode the change in Terraform and apply it** (or revert the console edit and do it properly in code). If you do nothing, the next `terraform plan` shows a diff and the next `apply` silently reverts the console fix — possibly re-opening the incident at the worst moment. Manual console edits are drift; Git (via Terraform) is the source of truth.
</details>

---

**Score yourself:** 5/5 — you're ready to own the IaC. 3–4 — re-read the golden rules. Below 3 — re-read the whole README, it's short. 🙂
