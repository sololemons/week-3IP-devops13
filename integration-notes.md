# KijaniKiosk Integration Notes and Conflict Resolution

## Executive Summary
Integrating strict security controls with production service requirements introduces predictable conflicts across configuration loading, health monitoring, log lifecycle management, and package integrity.

This document records the four integration challenges identified during the Friday deployment phase and the approved remediation patterns used to resolve them without weakening baseline hardening.

## Scope
This report covers:
- Systemd hardening interaction with application configuration
- Filesystem inheritance behavior for monitoring outputs
- Log rotation behavior with namespace isolation
- Package version pinning on potentially drifted virtual machines

## Integration Challenge A
### ProtectSystem=strict vs EnvironmentFile Access

#### Conflict
`ProtectSystem=strict` mounts broad host paths as read-only from the service perspective. The service still needs to read its environment file at:

`/opt/kijanikiosk/config/payments-api.env`

#### Resolution
Use targeted whitelisting via `ReadOnlyPaths` rather than reducing hardening level.

#### Decision
Add the following directive in the service unit:

```ini
ProtectSystem=strict
ReadOnlyPaths=/opt/kijanikiosk/config/
```

#### Rationale
- Preserves deny-by-default hardening posture.
- Allows only the required configuration path.
- Prevents service-side modification of sensitive environment data.

## Integration Challenge B
### Monitoring Output Permissions and ACL Defaults

#### Conflict
The Phase 8 health check writes a root-owned JSON artifact under:

`/opt/kijanikiosk/health/`

Without default ACL inheritance, newly created files can become unreadable to required non-root consumers.

#### Resolution
Apply Default ACLs on the directory so new files inherit required read access.

#### Access Model Update
| Path | Owner | Group | Base Mode | ACL Intent |
|---|---|---|---|---|
| `/opt/kijanikiosk/health/` | `root` | `kijanikiosk` | `750` | Root writes, group reads |
| Default ACL | `root` | `kijanikiosk` | `default:r--` | Ensure group-read on new files |

#### Rationale
- Eliminates permission drift for root-created files.
- Removes need for recurring manual chmod/chown fixes.
- Keeps least-privilege access model intact.

## Integration Challenge C
### logrotate Postrotate Behavior with PrivateTmp

#### Conflict
The logging service uses `PrivateTmp=true`.

- `systemctl restart` recreates process context and can disrupt private namespace continuity.
- `systemctl reload` fails when no `ExecReload` is defined.

#### Resolution
Use `SIGHUP` in postrotate to reopen file handles without restarting the process.

#### Implementation
```bash
postrotate
    /usr/bin/systemctl kill -s HUP kk-logs.service >/dev/null 2>&1 || true
endscript
```

#### Rationale
- Preserves service lifecycle and active context.
- Avoids unnecessary restarts and connection disruption.
- Aligns with standard daemon log-reopen behavior.

## Integration Challenge D
### Dirty VM State and Package Pinning

#### Conflict
Target hosts may already contain `nginx` at versions different from the pinned requirement. Blind package installation can trigger unverified upgrades or downgrades.

#### Resolution
Implement pre-flight version validation and fail loudly on mismatch.

#### Decision
- Query installed package version using `dpkg-query`.
- If installed version differs from pinned target, stop execution and require human review.

#### Rationale
- Prevents unsafe automatic downgrades or dependency mismatches.
- Protects system integrity in drifted environments.
- Forces explicit operator approval for version correction.

## Final Verification Matrix
| Challenge | Status | Resolution Mechanism |
|---|---|---|
| A: Config access under strict filesystem policy | Resolved | `ReadOnlyPaths` in systemd unit |
| B: Health file readability inheritance | Resolved | Default ACLs on health directory |
| C: Log rotation under `PrivateTmp` | Resolved | `SIGHUP` signaling in `postrotate` |
| D: Package pinning on drifted VM | Resolved | Pre-flight version validation |

## Conclusion
All identified integration conflicts are resolved using targeted, least-privilege patterns.

The resulting design preserves strict hardening while maintaining service operability, predictable rotation behavior, and controlled package lifecycle safety.
