# 🔐 Kubernetes Cluster Security Hardening

## Architecture
![Architecture](docs/architecture-diagram.png)

## Overview

This project documents the design and implementation of enterprise-grade cluster security across an Azure Kubernetes Service (AKS) environment. 

The containerized landscape is the new infrastructure perimeter. The traditional infrastructure model assumed that securing the cloud boundary or virtual network was enough to protect the workloads inside. That model collapsed with the rise of microservices, dynamic orchestration, and rapid CI/CD deployments. Today, an organization's most critical workloads live inside containers, communicating across a flat, highly dynamic internal network. Whoever compromises a single pod can potentially move laterally to compromise the entire cluster.

This project hardens that container orchestration layer using a multi-layered, zero-trust framework—enforcing Role-Based Access Control (RBAC), strict Network Policies, rigorous Pod Security Standards, cloud-native Secrets Management, and real-time runtime threat monitoring. This transforms a default, wide-open Kubernetes deployment into an active, resilient security environment that evaluates, isolates, and defends against threats in real time.

---

## The Problem This Solves

A default Kubernetes cluster is not secure. It is functional. There is an important difference.

Out of the box, standard Kubernetes configurations allow pods within a cluster to communicate with any other pod across namespaces without restriction. Containers frequently run as the `root` user, possess full write capabilities to the underlying host filesystem, and lack enforcement around privileged execution. Secrets are natively stored as weak, unencrypted Base64-encoded strings within the cluster database (`etcd`). Furthermore, there is no native system watching for behavioral anomalies—such as an attacker spawning a terminal shell inside a compromised container or reading sensitive system files.

This default configuration is the reason that container-based attacks—lateral movement, privilege escalation, and credential exfiltration—are incredibly damaging once a single public-facing application is breached. The blast radius within a default cluster is total.

This project implements specific open-source and cloud-native security controls to close these structural gaps systematically.

---

## Why Network Security Starts with Network Policies

Before defining how a workload should execute, the first architectural question to answer is: under what conditions should pods be allowed to talk to each other?

Kubernetes Network Policies are the cluster's internal firewall engine. They evaluate and govern layer 3 and 4 traffic boundaries. The critical architectural insight here is that network security must be designed around a **Default Deny** posture. A common mistake is leaving the network open and trying to write blocklists for specific services. The result is a brittle environment where new microservices are exposed by default, expanding the attack surface automatically.

I designed a zero-trust network topology where all ingress and egress traffic is blocked by default. Traffic is only permitted when explicitly whitelisted via label-based selectors. By isolating internal communication paths exclusively to required dependencies, the blast radius of a compromised front-end application is entirely contained, preventing lateral movement to backend databases or administrative namespaces.

---

## The Case for Restricted Pod Security Standards

Allowing containers to run with permanent, unmitigated privileges is one of the highest risk configurations in a Kubernetes environment.

Consider the attack scenario: an adversary exploits a remote code execution (RCE) vulnerability in a web application container. If that container is running as `root` with a writable root filesystem, the adversary can modify application binaries, install malicious tooling, or escape the container boundaries entirely to compromise the underlying node host. 

Enforcing the Kubernetes `restricted` Pod Security Standard fundamentally changes this model. Workloads are stripped of administrative capabilities: they must run as a non-root user, are barred from privilege escalation, and must operate with a completely read-only root filesystem. 

For an adversary, this drastically increases the cost of an attack. They cannot write scripts to disk, they cannot modify system configurations, and they cannot escalate privileges. While developers occasionally resist this due to the strict operational constraints it imposes on container design, a few architectural adjustments during deployment eliminate an enormous vector of exploitation.

---

## Secrets Store CSI Driver & External Vaulting

Natively, Kubernetes secrets are merely Base64 encoded. They are not securely encrypted at rest within the cluster by default, and managing them directly in cluster manifests creates a severe risk of accidental exposure in version control systems.

This project bridges cloud identity and cluster security by integrating **Azure Key Vault** directly using the **Secrets Store CSI Driver**. Rather than storing sensitive credentials like database passwords or API keys inside Kubernetes files, secrets remain securely hosted in a dedicated cloud vault. 

Pods pull these values dynamically at runtime, mounting them as localized volumes using managed identities. This eliminates hardcoded configuration files, establishes a clean audit trail outside the cluster, and ensures that secrets are never exposed in Git repositories.

---

## Runtime Threat Hunting with Falco

Static defenses, admission controllers, and firewall rules are vital, but they are only half the battle. Real-time runtime threat monitoring provides the visibility required to catch active breaches.

**Falco** acts as the cluster's internal security camera, parsing system calls directly from the Linux kernel to detect behavioral anomalies that static configurations miss. If a public-facing container suddenly executes a binary like `bash`, `sh`, or `zsh` to spawn a terminal shell, Falco flags it instantly. If an unauthorized process attempts to read sensitive system configuration files like `/etc/passwd` or `/etc/shadow`, an alert is generated.

This project implements custom Falco rules and rule calibrations to actively stream these alerts. The distinction here is between passive hardening and active defense: runtime security ensures that even if a zero-day vulnerability bypasses your configuration settings, the malicious activity is detected and isolated immediately.

---

## Implementation Decisions

### Report-Only/Audit Mode for Admission Controllers
To prevent widespread application downtime, strict Pod Security Standards were initially rolled out using `audit` and `warn` modes rather than immediate `enforce` mode. This allowed the logging infrastructure to capture which workloads would fail the new compliance checks without terminating active production pods, providing a safe runway to refactor manifests.

### Ephemeral Scratchpads (`emptyDir`)
To enforce a `readOnlyRootFilesystem: true` posture on applications that require temporary write access (such as Nginx logging or caching layers), I implemented localized `emptyDir` volume mounts. This creates an isolated, volatile RAM-backed scratchpad for the container to write to, keeping the core application filesystem completely immutable and locked down.

### Explicit Namespace Separation and Least-Privilege RBAC
Administrative authorization was decoupled by creating strict namespace boundaries backed by tailored ClusterRoles and Roles. Cluster administrators retain full scope, while developers and read-only auditors are tightly bound via RoleBindings to specific functional namespaces, preventing accidental or unauthorized cluster-wide modifications.

---

## Challenges Encountered

### 1. Taming the Admission Controller: Pod Security vs. Nginx
Enforcing the `restricted` Pod Security Standard routinely breaks standard, off-the-shelf container images.
*   **The Problem:** The official Nginx container image inherently relies on writing to `/var/cache/nginx/` and binding to privileged port `80`. Under a strict `readOnlyRootFilesystem: true` and non-root execution (`runAsUser: 1000`) policy, the container failed to boot entirely, falling into a continuous `CrashLoopBackOff`.
*   **The Solution:** The deployment manifest was re-architected. I injected localized `emptyDir` volumes mounted explicitly over `/var/cache/nginx`, `/var/run`, and `/tmp` to serve as ephemeral scratchpads. Additionally, a custom inline configuration was applied via container arguments to force Nginx to listen on the unprivileged port `8080`, successfully satisfying the security controller while preserving application functionality.

### 2. Missing Custom Resource Definitions (CRDs) for Secrets Store CSI
*   **The Problem:** During the initial deployment of the secrets architecture, applying the `SecretProviderClass` manifest resulted in immediate API errors stating the object type was unrecognized by the cluster.
*   **The Solution:** Kubernetes does not natively understand cloud-provider custom secrets architectures. The issue was resolved by leveraging the Azure CLI to explicitly install and enable the `azure-keyvault-secrets-provider` add-on. This automatically bootstrapped the necessary Custom Resource Definitions (CRDs) and daemonsets, establishing the proper handshake between AKS and Azure Key Vault via Managed Identities.

### 3. Git Synchronization Rejections (`--allow-unrelated-histories`)
*   **The Problem:** When pushing the finalized infrastructure and manifest code to the remote repository, Git rejected the push due to conflicting, unrelated commit histories between the local initialization environment and the default remote GitHub branch.
*   **The Solution:** I resolved this version control hurdle by executing a git pull with the explicit modifier `git pull origin main --allow-unrelated-histories`. This forced Git to merge the distinct tracking structures cleanly, allowing for a successful upstream production push without losing code integrity.

---

## Lessons Learned

The most critical takeaway from this project is that cluster security cannot exist in a vacuum separated from development workflows. 

A security architecture that is technically flawless on paper is an operational failure if it breaks the engineering pipeline. Forcing rigid constraints like read-only file systems or complex secret-mounting protocols without providing baseline templates or documentation only leads to developer bypasses, pushback, and friction. Security must be designed *with* application lifecycle reality in mind, deploying scaffolding (like pre-configured unprivileged base manifests) so teams can adopt secure patterns natively.

Secondly, change management dictates the success of container security. Moving a running environment from an open network to a default-deny posture requires careful mapping of application dependencies beforehand. Security engineering must spend equal time analyzing traffic logs and application telemetry as they do writing yaml manifests to ensure that protection does not come at the cost of availability.

---

## What I Would Do Differently at Scale

At enterprise scale, I would transition away from manual manifest applications and entirely embrace **GitOps workflows** via tools like **ArgoCD** or **Flux**. Managing cluster state through declarative Git repositories ensures that any unauthorized drift in configuration or security policies is automatically detected and remediated back to the hardened baseline.

For policy enforcement, I would replace native Pod Security Standards with dynamic admission controllers like **Kyverno** or **OPA Gatekeeper**. This allows for highly granular, business-specific policy rules—such as mandating that all images must originate exclusively from an authorized internal Azure Container Registry (ACR), or automatically injecting specific security contexts at mutation time.

Finally, I would implement a **Service Mesh** (such as Istio or Linkerd) to achieve true zero-trust networking. While Network Policies secure layers 3 and 4, a service mesh introduces automatic Mutual TLS (mTLS) for cryptographic identity verification between pods, providing robust layer 7 traffic management, end-to-end encryption, and deep observability across all microservices.

---

Uzma Shabbir
Azure Security Engineer | AZ-104 | AZ-500
[GitHub](https://github.com/UzmaSami) • [LinkedIn](https://linkedin.com/in/uzma-shabbir-034361128)
