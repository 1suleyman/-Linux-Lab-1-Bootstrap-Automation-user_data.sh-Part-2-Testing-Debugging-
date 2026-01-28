#!/bin/bash
# user_data.sh — Linux LAB_USERS, LAB_GROUPS & Permissions Lab 1 bootstrap
# Target: Amazon Linux / Ubuntu (cloud-init user-data)
# NOTE (lab-only): This sets plaintext passwords via chpasswd (insecure for real systems).

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

LAB_PASSWORD="${LAB_PASSWORD:-DevOps123!}"   # override by exporting LAB_PASSWORD in your template if you want
LAB_USERS=("user1" "user2" "user3")
LAB_GROUPS=("devops" "aws")

log() { echo "[lab1] $*"; }

log "Starting Lab 1 bootstrap..."

# --- 1) Create LAB_GROUPS (idempotent) ---
for g in "${LAB_GROUPS[@]}"; do
  if getent group "$g" >/dev/null; then
    log "Group exists: $g"
  else
    log "Creating group: $g"
    groupadd "$g"
  fi
done



# --- 2) Create LAB_USERS with home directories (idempotent) ---
for u in "${LAB_USERS[@]}"; do
  if id "$u" >/dev/null ; then
    log "User exists: $u"
  else
    log "Creating user (with home): $u"
    useradd -m -s /bin/bash "$u"
  fi
done

# --- 3) Set passwords (lab-only; idempotent enough for labs) ---
# chpasswd will (re)set the password each run; that's OK for repeatable labs.
log "Setting lab passwords for LAB_USERS (lab-only)"
for u in "${LAB_USERS[@]}"; do
  echo "${u}:${LAB_PASSWORD}" | chpasswd
done

# --- 4) Primary vs supplementary group changes ---
# Set primary group to devops for user2 + user3
log "Setting primary group 'devops' for user2 and user3"
usermod -g devops user2
usermod -g devops user3

# Add aws as supplementary group for user1 (append safely)
log "Adding supplementary group 'aws' for user1"
usermod -aG aws user1

# --- 5) Create directory + file structure ---
log "Creating directory structure"
mkdir -p \
  /dir1 \
  /dir2/dir1/dir2/dir10 \
  /dir4 \
  /dir5 \
  /dir6 \
  /dir7/dir10 \
  /dir8 \
  /opt/dir14/dir10

log "Creating files"
touch /dir1/f1 /f2

# --- 6) Ownership + group assignment practice ---
log "Changing group ownership to devops for /dir1 /dir7/dir10 /f2"
chgrp devops /dir1 /dir7/dir10 /f2

log "Changing user ownership to user1 for /dir1 /dir7/dir10 /f2"
chown user1 /dir1 /dir7/dir10 /f2

# --- 7) Verification outputs (helpful in cloud-init logs) ---
log "Verification: LAB_GROUPS"
getent group devops aws || true

log "Verification: LAB_USERS"
getent passwd user1 user2 user3 || true

log "Verification: id output"
id user1 || true
id user2 || true
id user3 || true

log "Verification: directory/file ownership"
ls -ld /dir1 /dir7/dir10 /f2 || true

log "Lab 1 bootstrap complete."
