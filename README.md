# KijaniKiosk Infrastructure Hardening (Week 3)

## Overview
This repository contains the provisioning automation, security hardening decisions, and verification evidence for the KijaniKiosk Week 2 DevOps security exercise.

The implementation focuses on:
- Least-privilege service isolation
- Systemd sandboxing hardening
- ACL-based shared log access
- Firewall micro-segmentation
- Idempotent provisioning and post-remediation verification

## Objectives
- Build a reproducible hardened service environment for `kk-api`, `kk-payments`, and `kk-logs`
- Prevent privilege escalation and lateral movement
- Preserve service operability under strict security controls
- Verify that controls remain effective after events like log rotation and reboot

## Repository Structure

| Path | Description |
|---|---|
| `kijanikiosk-provision.sh` | Main provisioning script. Installs dependencies, creates users/groups, applies permissions/ACLs, writes systemd units, configures journald/logrotate/UFW, and runs verification checks. |
| `access-model.md` | Access model verification report covering ownership, POSIX permissions, ACL inheritance, and shared-log write continuity. |
| `kk-payments-hardening.md` | Technical hardening report for `kk-payments`, including sandboxing controls, runtime conflicts, and calibrated settings. |
| `integration-notes.md` | Integration conflict-resolution notes (strict filesystem policy, ACL defaults, logrotate behavior, and package pinning). |
| `hardening-decisions.md` | Executive-level risk and mitigation briefing with control matrix and residual risk summary. |
| `post-remediation-verification.md` | Final remediation verification for log access and rotation persistence. |
| `pre-provisioning-audit.txt` | Baseline pre-provisioning audit snapshot (users, ACLs, firewall, package holds, services). |
| `provision-run.log` | Detailed first provisioning run output. |
| `provision-run-clean.log` | Re-run output demonstrating idempotent behavior and clean validation. |
| `screenshots/` | Evidence images referenced by the markdown reports. |

## Security Controls Implemented
- Service identity isolation (`kk-api`, `kk-payments`, `kk-logs`)
- Filesystem restrictions (`ProtectSystem`, `ProtectHome`, scoped `ReadWritePaths`)
- Kernel/device hardening (`PrivateDevices`, `ProtectKernel*`, `ProtectControlGroups`)
- Privilege ceilings (`NoNewPrivileges`, `CapabilityBoundingSet=`)
- Syscall and address family restrictions (calibrated for Node.js)
- ACL inheritance for shared logs and health visibility
- Firewall intent rules for controlled ingress and payment-path protection
- Package pinning and hold policy for deployment stability

## Prerequisites
- Ubuntu/Debian-based Linux host
- Root privileges (`sudo`)
- Internet access for package repositories
- Expected deploy source directory: `/home/ubuntu/deploy`

## Quick Start
Run provisioning as root:

```bash
sudo bash kijanikiosk-provision.sh
```

## What the Script Does (Phase Flow)
1. Installs and pins core packages (`nginx`, `nodejs`, `acl`, `ufw`, and dependencies)
2. Creates/validates service accounts and group membership
3. Creates directory architecture and applies ownership/ACLs
4. Configures persistent journald and logrotate policy
5. Deploys app files and hardened systemd units
6. Resets and applies UFW firewall rules
7. Runs end-to-end verification and writes health status JSON

## Verification and Evidence
Verification outcomes are documented in:
- `post-remediation-verification.md`
- `access-model.md`
- `integration-notes.md`
- `kk-payments-hardening.md`

Visual evidence is stored in `screenshots/` and embedded in the reports.

## Notes and Assumptions
- The environment may be intentionally "dirty" before provisioning; script logic is designed to be idempotent.
- Some controls were calibrated to preserve Node.js runtime stability while maintaining strong containment.
- Report files are intended as audit artifacts for both technical and non-technical review.

