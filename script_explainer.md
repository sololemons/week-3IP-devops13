# KijaniKiosk Provisioning Script Explainer

## Purpose
This document explains what `kijanikiosk-provision.sh` does, how it is organized, and why each phase exists.

The script is designed to take a potentially "dirty" Linux host and converge it into a hardened, repeatable KijaniKiosk runtime environment.

## Script at a Glance

- Script file: `kijanikiosk-provision.sh`
- Shell mode: `set -euo pipefail` for strict failure handling
- Target base path: `/opt/kijanikiosk`
- Main service identities:
  - `kk-api`
  - `kk-payments`
  - `kk-logs`
- Primary group: `kijanikiosk`
- Key pinned package: `nginx=1.24.0-2ubuntu7.6`

## Design Goals

- Enforce least privilege using dedicated service users and group controls
- Apply hardened systemd service definitions
- Preserve shared logging interoperability using ACLs
- Lock package versions to reduce drift and unexpected updates
- Constrain network exposure with UFW intent-based rules
- Verify security and runtime state before declaring success

## Inputs and Assumptions

The script assumes:

- Root privileges are available
- Source JavaScript artifacts are present under `/home/ubuntu/deploy`
  - `api-server.js`
  - `payment-service.js`
  - optional `log-service.js` (a placeholder is generated if missing)
- The host may already have users, files, ACLs, firewall rules, and services configured

## Outputs Produced by the Script

- Directory tree under `/opt/kijanikiosk` with controlled ownership and permissions
- Config files under `/opt/kijanikiosk/config`
- Hardened unit files:
  - `/etc/systemd/system/kk-api.service`
  - `/etc/systemd/system/kk-payments.service`
  - `/etc/systemd/system/kk-logs.service`
- Journald config drop-in:
  - `/etc/systemd/journald.conf.d/kijanikiosk.conf`
- Logrotate policy:
  - `/etc/logrotate.d/kijanikiosk`
- Health verification JSON:
  - `/opt/kijanikiosk/health/last-provision.json`

## Phase-by-Phase Breakdown

## Phase 1: Package Management (`provision_packages`)

What it does:
- Checks currently installed `nginx` version
- Fails fast if installed version does not match pinned version
- Installs dependencies (`curl`, `gnupg`, `acl`, `ufw`)
- Configures NodeSource repository for Node.js 20
- Installs pinned `nginx` and `nodejs`
- Applies `apt-mark hold` on `nginx` and `nodejs`

Why it matters:
- Prevents silent package drift
- Enforces predictable, auditable package state

## Phase 2: Service Accounts (`provision_users`)

What it does:
- Ensures `kijanikiosk` group exists
- Creates/validates service accounts (`kk-api`, `kk-payments`, `kk-logs`)
- Ensures existing service accounts are in the expected group
- Creates or updates developer user `lemonsthedev` membership

Why it matters:
- Implements identity isolation for services
- Supports least privilege and blast-radius reduction

## Phase 3: Directory Architecture and ACLs (`provision_dirs`)

What it does:
- Creates directories for:
  - application code
  - shared logs
  - health artifacts
  - configuration files
- Sets ownership and permission modes
- Applies ACLs for shared log write interoperability (`kk-api`, `kk-payments`)
- Applies health-directory ACL defaults for readable monitoring output
- Bootstraps `payments-api.env` if not already present

Why it matters:
- Makes file-system permissions deterministic
- Prevents post-rotation or post-write access regressions

## Phase 4: App Deployment and systemd Hardening (`provision_services`)

What it does:
- Copies app source artifacts into target directories
- Creates environment files in `/opt/kijanikiosk/config`
- Writes hardened systemd unit files for all three services
- Reloads systemd and enables/starts services

Hardening themes used:
- Filesystem restrictions (`ProtectSystem`, `ReadOnlyPaths`, `ReadWritePaths`)
- Privilege restrictions (`NoNewPrivileges`, `CapabilityBoundingSet`)
- Kernel and namespace protections
- Syscall filtering and address family limitations

Why it matters:
- Converts policy decisions into enforceable runtime controls
- Starts services with secure defaults by design

## Phase 5: Journald Persistence and Log Rotation (`provision_logging`)

What it does:
- Enables persistent journal storage with size limits
- Writes logrotate policy for app logs
- Uses `systemctl kill -s HUP` in postrotate hooks for log handle reload

Why it matters:
- Preserves logs across reboot
- Rotates logs safely without unnecessary full service restarts

## Phase 6: Firewall Policy (`provision_firewall`)

What it does:
- Resets UFW state
- Sets default `deny incoming` and `allow outgoing`
- Allows loopback access for local payment proxy path
- Allows selected CIDR ingress for SSH/HTTP/health checks
- Explicitly denies external access to payment service port
- Enables UFW

Why it matters:
- Enforces least-exposure network posture
- Reduces direct attack surface for sensitive services

## Phase 7: Verification and Health Checks (`verify_state`)

What it checks:
- Service accounts and required directories exist
- No dangerous SUID files in app tree
- Package holds remain active
- Services are enabled and listening on expected ports
- Health JSON is generated with current status
- Logrotate syntax is valid
- ACL/write behavior survives forced rotation
- UFW rules match expected intent

Failure behavior:
- Any failed check increments a counter
- Script exits non-zero if one or more checks fail

Why it matters:
- Prevents "looks-configured" false positives
- Produces a confidence gate before declaring readiness

## Security Model Summary

The script enforces a layered hardening model:

- Identity isolation: dedicated service users
- Filesystem control: targeted read/write boundaries
- Privilege ceilings: no escalation paths for services
- Kernel/namespace guardrails: reduced host-level interaction
- Network micro-segmentation: strict ingress intent
- Operational resilience: idempotent convergence and runtime verification

## Operational Notes

- This script is intended to be idempotent for repeated execution on already-configured hosts.
- Log and firewall rules are actively reconciled to desired state on each run.
- The script is strict by design and will fail fast on critical drift (for example, pinned `nginx` mismatch).

## How to Run

```bash
sudo bash kijanikiosk-provision.sh
```

## Success Signal

A successful run ends with:

- `All verification checks passed! Server is ready.`
- `Provisioning complete!`

If either is missing, inspect the logged `FAIL` or `CRITICAL` lines and remediate before re-running.
