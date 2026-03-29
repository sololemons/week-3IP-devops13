# Access Model Verification Report

## Overview
This report documents the current access control configuration for the KijaniKiosk infrastructure.

The verification focuses on:
- Service interoperability across shared directories
- Correct propagation of inherited permissions through Default ACLs
- Post-rotation access continuity for log-writing services

## Directory Permissions Summary
The table below summarizes standard POSIX ownership and effective service-level intent across primary paths.

| Directory | Owner:Group | User Permissions | Group Permissions | Notes |
|---|---|---|---|---|
| API Source | `kk-api:kijanikiosk` | `rwx` (full) | `r-x` (read/execute) | Standard service lockdown |
| Health Monitoring | `root:kijanikiosk` | `rwx` (full) | `r-x` (read/execute) | Restricted to root and group |
| Shared Logs | `kk-logs:kijanikiosk` | `rwx` (full) | `rwx` (full) | Extended ACLs and defaults active |

## Shared Logs: Extended ACL Analysis
The shared logs path uses Linux ACLs to support controlled multi-user write access, which standard POSIX mode bits alone cannot reliably provide.

### Current ACL State
| Control Area | Verification |
|---|---|
| Named user access | Both `kk-payments` and `kk-api` have explicit `rwx` ACL entries |
| Inheritance defaults | `default:` ACL entries are present to propagate permissions to newly created files |
| Operational impact | Prevents post-rotation "Permission Denied" errors in shared log workflows |

## Post-Rotation Verification
A test file was created to confirm ACL inheritance continues to apply after rotation.

### File Metadata
| Field | Value |
|---|---|
| Path | `/opt/kijanikiosk/shared/logs/test-write.tmp` |
| ACL indicator | `+` in mode string (example: `-rw-rw-r--+`) confirms extended ACL presence |

### Effective Rights Observation
> [!IMPORTANT]
> **Mask Restriction Confirmed**
>
> ACL entries may grant `rwx`, but effective access for the test file is currently `rw-`.
> This is expected when mask or standard mode bits (for example, from `umask 002`) filter out execute (`x`).
>
> This is the desired security posture for log files: readable and writable by required services, but not executable.

## Final Status
**SUCCESS**

The access-control model is operating correctly:
- `kk-payments` and `kk-api` can write to the shared log directory
- Default ACL inheritance keeps newly created log files accessible
- No manual permission remediation is required after routine log rotation
