# KijaniKiosk Executive Security & Risk Mitigation Briefing

## Strategic Security Overview

KijaniKiosk's digital infrastructure has been successfully transitioned from a functional prototype into a **resilient, production-ready environment** designed to withstand modern cyber threats.

### Core Objective
Ensure that a breach affecting one component of the platform **cannot cascade into full system compromise**. We implemented multiple layers of internal protection that act as invisible **digital partitions**, significantly reducing the likelihood of unauthorized data exposure or service disruption.

### Guiding Principle
Each security control balances **high availability for customers** with a strict **Zero-Trust internal posture**. Under this model, even trusted internal software is granted only the minimum permissions required to perform its function.

### Risk Mitigation Scope
If an attacker exploits a vulnerability in our public-facing systems, internal safeguards prevent them from:

- Accessing financial transaction systems
- Reading sensitive logs
- Modifying operational configurations
- Moving laterally across services

### Additional Benefits
We have reduced the risk of accidental misconfiguration and insider error by:

- Automating permission management
- Enforcing consistent deployment standards
- Eliminating temporary security gaps during manual changes

### Alignment with Industry Standards
Our architecture aligns with widely accepted cybersecurity principles:

- **Least Privilege** — Services have only minimum required permissions
- **Zero Trust Architecture** — All components treated as potential risks
- **Defense in Depth** — Multiple independent protection layers
- **Secure Configuration Management** — Consistent, auditable deployments

---

## Security Controls & Risk Matrix

The table below maps each control to its operational purpose and primary risk mitigation.

| Control | Function | Risk Mitigated |
|---|---|---|
| **Identity Isolation** | Assigns each software component a unique operating identity | Prevents vulnerability in one service from compromising the entire platform |
| **Filesystem Immutability** | Locks critical OS areas into read-only mode during service execution | Stops attackers from installing persistent malware or modifying system files |
| **Service Sandboxing** | Restricts each service to a limited view of system resources | Prevents compromised services from accessing sensitive configuration or credentials |
| **Network Micro-segmentation** | Limits communication pathways between services | Blocks lateral movement across internal systems |
| **Privilege Ceiling** | Removes ability for services to gain administrative privileges | Prevents escalation from minor vulnerabilities to full system control |
| **Automated Version Pinning** | Locks software dependencies to approved, tested versions | Prevents unexpected or malicious updates from affecting stability or security |
| **Inherited Access Controls** | Automatically applies correct permissions to newly created logs and files | Prevents accidental exposure of sensitive operational data |
| **Hardware Resource Shielding** | Prevents services from interacting with physical hardware | Protects against advanced persistence and data extraction techniques |

---

## Defensive Architecture: Process Containment

Our security strategy centers on **Process Containment**.

### Traditional Deployment Risk
In typical deployments, compromising one application provides attackers broad visibility into the server environment. This enables lateral movement and potential full system takeover.

### Hardened KijaniKiosk Approach
Each service operates within tightly controlled boundaries. If an attacker gains access to the API layer, they encounter significant restrictions:

- Cannot access the payment processing service
- Cannot read private temporary system files
- Cannot modify runtime configuration
- Cannot install persistent software
- Cannot escalate privileges

This confines any breach to a limited operational scope, preventing escalation into full system takeover.

### Dirty Environment Risk Mitigation
We address the **Dirty Environment Risk** — unauthorized changes or legacy software persisting unnoticed into production.

Our deployment process now verifies:

- Software versions match approved pins
- System state aligns with expected configuration
- Previous changes have not silently persisted

This ensures that:
- Unauthorized changes cannot silently persist
- Production environments remain consistent and auditable
- Deployments are reproducible and compliant with standards

---

## Control Implementations

### 1. Identity Isolation
**Concept:** Assigning unique identities to each software component.

**Implementation:**
- Three distinct service accounts: `kk-api`, `kk-payments`, `kk-logs`
- Operating system treats them as completely separate "people"

**Security Benefit:**
If a hacker finds a bug in the API, they become trapped in the `kk-api` identity. The OS prevents them from viewing or accessing Payments service files or processes.

---

### 2. Filesystem Immutability (ProtectSystem=strict)
**Concept:** Locking the operating system into a "Read-Only" state for the service.

**Implementation:**
- Enabled `ProtectSystem=strict` for the Payments service
- Critical OS paths become read-only from service perspective

**Security Benefit:**
Even if an attacker gains control of payment software, they cannot:
- Change the system's time
- Install hidden "backdoor" programs
- Modify server network settings

The system is effectively "frozen" to compromised processes.

---

### 3. Service Sandboxing (Private Isolation)
**Concept:** Restricting services to a limited view of system resources.

**Implementation:**
- `PrivateTmp=yes` provides isolated temporary filesystem
- Restricted `EnvironmentFile` access
- Each service receives only its own private workspaces

**Security Benefit:**
Most applications share a common "junk drawer" (`/tmp`). We give each service its own private, invisible drawer. No other software can peek inside to see temporary transaction data.

---

### 4. Inherited Access Controls (Default ACLs)
**Concept:** Automatically applying safety rules to newly created data.

**Implementation:**
- Default ACLs on `/opt/kijanikiosk/health/` directory
- New files automatically inherit required permissions
- No manual intervention required after file creation

**Security Benefit:**
When the system (root) creates a health report, it would normally be locked to system-only access. Our ACL template ensures every new report is automatically readable by authorized monitoring staff without daily manual unlocking.

---

### 5. Network Micro-segmentation
**Concept:** Limiting communication pathways so services only communicate with intended partners.

**Implementation:**
- UFW (Uncomplicated Firewall) with strict rules
- External access to Payments Service (port 3001) completely blocked
- Only local Nginx reverse proxy permitted to communicate with Payments

**Security Benefit:**
If a hacker attempts to bypass the website and connect directly to the payment processor from the internet, the firewall drops the connection immediately. This creates a bank-vault model where the processor can only be accessed by specific internal systems.

---

### 6. Privilege Ceiling
**Concept:** Removing "Master Key" (administrative) powers from software.

**Implementation:**
- `CapabilityBoundingSet=` (empty)
- `NoNewPrivileges=yes`
- Applied to both `kk-payments.service` and `kk-logs.service`

**Security Benefit:**
Even if a hacker discovers a privilege escalation bug, the operating system refuses to grant administrative rights. The process is **physically incapable** of becoming an administrator, regardless of clever exploitation techniques.

---

### 7. Automated Version Pinning
**Concept:** Locking software to a specific, "known-good" version.

**Implementation:**
- `apt-mark hold` for Nginx (1.24.0) and Node.js
- Pre-flight "Fail Loudly" checks before installation
- Installation stops if server version doesn't match approved version

**Security Benefit:**
If a third-party software company releases a broken update on a Friday night, our server ignores it and stays on the tested, stable version. We avoid crashes and ensure predictable, auditable deployments.

---

### 8. Hardware Resource Shielding
**Concept:** Preventing software from accessing physical hardware of the server.

**Implementation:**
- `PrivateDevices=yes` — Hide disks, USB ports, and hardware
- `ProtectKernelModules=yes` — Prevent driver installation or OS core alteration
- `ProtectControlGroups=yes` — Lock out from resource management settings
- `ProtectClock=yes` — Restrict system time manipulation

**Security Benefit:**
A sophisticated attacker gaining entry to the Payment service cannot:
- Install keyloggers to capture keystrokes
- Deploy firmware rootkits (hardware-embedded viruses)
- Persist attacks across reboots
- Access the "padded room" walls or internal wiring

---

## Residual Risk Considerations

While implemented safeguards significantly reduce attack likelihood and impact, some external risks remain outside this hardening phase.

### Supply Chain Risk
**Scope:** System relies on trusted external software libraries.

**Risk:** If a third-party vendor is compromised upstream, malicious code could be introduced before reaching our environment.

**Future Mitigation Direction:**
- Dependency verification
- Software integrity validation
- Artifact signing

---

### Insider Threat Risk
**Scope:** Security controls limit accidental misuse by authorized personnel.

**Risk:** A fully authorized administrator could intentionally perform destructive actions.

**Future Mitigation Direction:**
- Role separation and principle of least privilege
- Comprehensive audit logging
- Approval workflows for critical actions

---

### Distributed Denial of Service (DDoS)
**Scope:** Current architecture lacks upstream traffic filtering.

**Risk:** Large-scale malicious traffic can overwhelm the public storefront.

**Future Mitigation Direction:**
- Rate limiting
- Content Delivery Network (CDN) integration
- Upstream traffic filtering layers

---

## Executive Summary

KijaniKiosk now operates within a hardened infrastructure designed to:

✅ Prevent lateral movement between services  
✅ Minimize the blast radius of any compromise  
✅ Ensure consistent and repeatable deployments  
✅ Protect sensitive transaction pathways  
✅ Reduce operational security risk from human error  

The current implementation provides a strong security baseline aligned with industry best practices while identifying clear next steps for continued maturity.

This structured approach ensures that security evolves alongside the platform as business requirements grow.
