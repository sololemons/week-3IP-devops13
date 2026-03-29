# Post-Remediation Verification: Log Access and Rotation

## Objective
This verification confirms that the **Least Privilege Model** and configured **Access Control Lists (ACLs)** remain effective after log rotation events.

In many Linux environments, `logrotate` creates new log files as `root`, which can unintentionally block service users from writing logs. This test validates that the current hardening prevents that failure mode.

## Verification Steps and Results

### 1. Forced Log Rotation
The rotation policy was executed manually:

```bash
sudo logrotate --force /etc/logrotate.d/kijanikiosk
```

**What happened:**
- Existing logs were archived.
- A new log file structure was created.

**Risk being tested:**
- Without correct default ACL inheritance, newly created log files may revert to restrictive permissions and deny `kk-api` write access.

### 2. Definitive Write Test as Service User
A write operation was performed as the application user:

```bash
sudo -u kk-api touch /opt/kijanikiosk/shared/logs/test-write.tmp && echo "PASS..."
```

**Observed result:**
- `PASS: kk-api can write after logrotate`

**Interpretation:**
- The unprivileged `kk-api` identity successfully wrote into a logs directory managed by `kk-logs`.
- This confirms intended cross-user write permissions are functioning after rotation.

### 3. ACL Inheritance Validation (`getfacl`)
The ACL output confirms expected inheritance and enforcement:

- `owner: kk-api`
  - Confirms file creation occurred under the correct service identity.
- `user:kk-api:rwx #effective:rw-`
  - Demonstrates inherited ACL permissions are present.
  - Effective access is correctly limited by mask.
- `mask::rw-`
  - Enforces a security ceiling.
  - Prevents execute permissions in the log path while preserving read/write access.

### 4. Final Permission State (`ls -lh`)
The file mode indicator includes `+` (for example, `-rw-rw-r--+`), confirming that extended ACL attributes are present on the new files.

## Conclusion
The remediation is **successful**.

The `kk-api` service is now **rotation-proof** and can continue writing logs reliably after scheduled log rotation, without requiring manual permission correction.
