# 🐧 Linux Lab 1 Bootstrap Automation (user_data.sh) — Part 2 (Testing + Debugging)

> **Bear in mind:** this lab is split into two parts.
> [Part 1](https://github.com/1suleyman/-Linux-Users-Groups-Bootstrap-Automation-Lab-user_data.sh-Part-1-Code-Walkthrough-) was the code walkthrough (explaining the script).
> **Part 2 (this README)** is the **real test on EC2**, including debugging why it failed, fixing it, and validating the results.

In this lab, I wired my `user_data.sh` into Terraform, launched an EC2 instance, then validated whether cloud-init actually executed my bootstrap. It **failed first**, and I debugged it end-to-end using cloud-init logs, environment reproduction (`env -i`), and script inspection. After two key fixes, it **worked successfully**.

---

## 📋 Lab Overview

**Goal:**

* Attach a Bash bootstrap script to an EC2 instance using Terraform `user_data`
* Validate execution via cloud-init logs
* Debug failures using:

  * `/var/log/cloud-init-output.log`
  * tailing logs
  * inspecting the executed script (`/var/lib/cloud/instance/scripts/part-001`)
  * reproducing cloud-init PATH issues with `env -i`
* Fix root causes and re-run Terraform to confirm success

**Learning Outcomes:**

* Understand Terraform `file()` paths (absolute vs relative)
* Validate user_data execution with grep + sentinel log lines
* Use cloud-init logs as “ground truth” for bootstrap success/failure
* Diagnose “command not found” issues caused by missing PATH in non-interactive environments
* Learn that `groups` is a **reserved Bash variable** (breaks arrays silently)
* Build more robust lab scripts using `LAB_*` prefixes to avoid name collisions
* Make an engineering decision: when automation is worth it vs when documentation is enough

---

## 🛠 Step-by-Step Journey

### Step 1: Attach `user_data.sh` to Terraform EC2 Resource

**Task:** Add user_data to `aws_instance` using `file()`.

**First attempt (wrong path):**

```hcl
user_data = file("/user_data.sh")
```

**Fix:** A leading `/` means “start at filesystem root” (absolute path).
Because `user_data.sh` is in the same folder as `main.tf`, I should use a **relative path**:

```hcl
user_data = file("user_data.sh")
```

✅ Terraform will read the file from the current working directory.

---

### Step 2: Deploy Infrastructure

**Commands:**

```bash
terraform init
terraform plan
terraform apply
```

✅ Apply succeeded and EC2 launched.

---

### Step 3: SSH into the Instance

**Commands:**

```bash
chmod 400 "labec2.pem"
ssh -i "labec2.pem" ec2-user@<public-dns>
```

Now the real question became:

> **Did cloud-init actually run my script successfully?**

---

### Step 4: Validate Script Completion via Sentinel Log Line

My script prints a final “sentinel” log line:

> `[Lab 1] Lab 1 bootstrap complete`

So I searched for it in cloud-init output logs:

```bash
sudo grep -n "Lab 1 bootstrap complete" /var/log/cloud-init-output.log
```

**What happened:** it printed nothing.

✅ That told me immediately: **the script didn’t reach the end**.

---

### Step 5: Debug Using the Last 200 Lines of cloud-init Output

To see what actually went wrong:

```bash
sudo tail -n 200 /var/log/cloud-init-output.log
```

**Why this works:**

* `tail` reads from the **bottom** of the file
* `-n 200` shows only the last 200 lines (fast, focused debugging)

**What I saw:**

* `id user1: no such user`
* `group 'devops' does not exist`
* other errors showing the script didn’t perform the early setup steps

✅ This confirmed: cloud-init *ran something*, but my script’s core commands weren’t successfully executing.

---

### Step 6: Inspect the Exact user-data Script cloud-init Executed

Cloud-init saves the executed script here:

```bash
sudo ls -l /var/lib/cloud/instance/scripts/
```

I found:

* `part-001`

Then I viewed the first 200 lines:

```bash
sudo sed -n '1,200p' /var/lib/cloud/instance/scripts/part-001
```

✅ The script content looked correct — so the issue wasn’t “Terraform didn’t upload the file”.

---

### Step 7: Test Whether Commands Exist (Binary vs PATH Problem)

I checked if key commands exist on the AMI:

```bash
command -v groupadd || echo "groupadd not found"
command -v useradd  || echo "useradd not found"
command -v usermod  || echo "usermod not found"
command -v chpasswd || echo "chpasswd not found"
```

**Result:** they all existed (e.g. `/usr/sbin/groupadd`).

✅ So the binaries were installed.

**New hypothesis:**

> cloud-init’s environment **did not include** `/usr/sbin` in `$PATH`, so the script couldn’t find admin commands like `groupadd`.

---

### Step 8: Reproduce cloud-init Environment Using `env -i`

To mimic a “bare bones” environment:

```bash
sudo env -i bash -c 'echo "$PATH"; command -v groupadd || echo "groupadd not on PATH"'
```

**What it proved:**

* PATH was minimal
* `groupadd` was **not discoverable via PATH**

✅ This matched the cloud-init behavior.

---

### Step 9: Fix #1 — Export a Safe PATH in the Script

I added this **right after** `set -euo pipefail`:

```bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
```

Why this matters:

* cloud-init / cron / systemd / CI jobs often run with minimal PATH
* scripts must not rely on “login shell defaults”

---

## 🧨 Part 3: Second Failure — Reserved Bash Variable (`groups`)

After fixing PATH, the script **still failed**.

This time the clue was in the logs:

> it was iterating weird values like `0` instead of `devops` / `aws`

Root cause:

✅ `groups` is a **special read-only Bash variable**.
So my array declaration:

```bash
groups=(devops aws)
```

didn’t behave normally — and my loop never iterated over the real group names.

---

### Step 10: Fix #2 — Rename Arrays to Lab-Prefixed Names

I renamed:

* `users` → `LAB_USERS`
* `groups` → `LAB_GROUPS`
* kept `LAB_PASSWORD` as-is

Example:

```bash
LAB_USERS=(user1 user2 user3)
LAB_GROUPS=(devops aws)
```

And I updated **every loop reference**:

```bash
for g in "${LAB_GROUPS[@]}"; do ...
for u in "${LAB_USERS[@]}"; do ...
```

✅ Key lesson: change the variable name **and** every usage in loops.

---

### Step 11: Redeploy and Validate Success

Re-ran:

```bash
terraform plan
terraform apply
```

Then validated the sentinel line again:

```bash
sudo grep -n "Lab 1 bootstrap complete" /var/log/cloud-init-output.log
```

✅ Success:

* It returned something like: `95:[Lab 1] Lab 1 bootstrap complete`

That proved the script reached the end.

---

## ✅ Final Validation Commands (Post-Fix)

### Confirm groups exist

```bash
getent group devops aws
```

### Confirm users exist

```bash
getent passwd user1 user2 user3
```

### Confirm ownership/group ownership on directories/files

```bash
ls -ld /dir7 /dir10 /dir1
ls -ld /dir1/f1 /dir1/f2
```

### Confirm group memberships

```bash
id user1
id user2
id user3
```

✅ Observed outcomes:

* `devops` and `aws` groups exist
* `user1`, `user2`, `user3` exist with `/bin/bash`
* `user2` + `user3` primary group is `devops`
* `user1` includes `aws` as a supplementary group
* directories/files exist with expected owner + group owner (e.g., owner `user1`, group owner `devops`)

---

## ✅ Key Commands Summary

| Task                             | Command                                                                      |   
| -------------------------------- | ---------------------------------------------------------------------------- |
| Attach script in Terraform       | `user_data = file("user_data.sh")`                                           |  
| Find “completion” log line       | `sudo grep -n "Lab 1 bootstrap complete" /var/log/cloud-init-output.log`     |   
| View last log errors quickly     | `sudo tail -n 200 /var/log/cloud-init-output.log`                            |   
| List executed cloud-init scripts | `sudo ls -l /var/lib/cloud/instance/scripts/`                                |  
| View executed script content     | `sudo sed -n '1,200p' /var/lib/cloud/instance/scripts/part-001`              |   
| Check if command exists          | `command -v groupadd`                                                        |  
| Reproduce minimal PATH           | `sudo env -i bash -c 'echo "$PATH"; command -v groupadd echo "groupadd not on PATH"'`|  
| Fix PATH in script               | `export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"` |  
| Avoid reserved vars              | Use `LAB_USERS`, `LAB_GROUPS` (not `groups`)                                 |  

---

## 💡 Notes / Tips (What I Learned)

* **Cloud-init is not a normal login shell.** PATH can be missing `/usr/sbin`.
* A script can fail with “command not found” even when the tool is installed — because it’s not on PATH.
* `env -i` is an excellent way to mimic “early boot” environments.
* `groups` is a **reserved Bash variable** → using it as an array name can silently break logic.
* Better practice: prefix lab variables like:

  * `LAB_USERS`
  * `LAB_GROUPS`
  * `LAB_PASSWORD`

---

## 🧠 Engineering Reflection: Automation vs Leverage

This lab worked and taught me real automation instincts — but it also made me reflect on leverage:

If:

* manual copy/paste from a documented README takes **1–2 minutes**, and
* writing + debugging automation takes **hours**, and
* the lab is **ephemeral** (destroyed + recreated often),

then manual + strong documentation can be the smarter choice.

**When automation is worth it:**

* repeated many times
* must reduce human error
* scales across environments/teams
* part of CI/CD or production pipelines

**For one-off learning labs:**

* “manual + documented” can be faster and more reliable

✅ Key mindset:

> Automation is a tool — not the goal.

---

## 📌 Lab Summary

| Step                                      | Status | Key Takeaway                                                   |
| ----------------------------------------- | ------ | -------------------------------------------------------------- |
| Add `user_data = file(...)`               | ✅      | Relative paths matter (`"user_data.sh"` not `"/user_data.sh"`) |
| Deploy and SSH                            | ✅      | Infrastructure successful                                      |
| Validate via cloud-init logs              | ✅      | `cloud-init-output.log` is the ground truth                    |
| Debug failure with `tail`                 | ✅      | Find errors fast                                               |
| Inspect executed script                   | ✅      | Confirm what actually ran (`part-001`)                         |
| Fix missing PATH                          | ✅      | Cloud-init may not include `/usr/sbin`                         |
| Fix reserved var bug (`groups`)           | ✅      | Bash semantics can break automation silently                   |
| Final validation (users/groups/ownership) | ✅      | End state confirmed                                            |
| Terraform destroy                         | ✅      | Clean teardown after validation                                |
