# System Overview - OmIronClaw

## Objective

Define a hardware-agnostic, security-first architecture for Debian 13 hosts running local and/or hybrid AI services.

## Core Components

| Component | Role | Recommended Bind | Notes |
|-----------|------|------------------|-------|
| SSH | Remote administration | 0.0.0.0:22 (restricted by firewall) | Key-only auth |
| Caddy | TLS termination and routing | 0.0.0.0:443 and 80 | API auth at gateway |
| Ollama | Local inference engine | 127.0.0.1:11434 | Access through Caddy |
| OpenClaw | Agent orchestration gateway | 127.0.0.1:18789 | Access through Caddy paths |
| nftables | Boundary protection | Kernel firewall | Default deny inbound |
| AppArmor | Mandatory access control | Kernel LSM | Enforce for exposed services |

## Security Layers

1. Boundary: nftables deny-by-default plus provider firewall/security groups (for VPS).
2. Access: SSH key-only, explicit allow users, rate limiting.
3. Service isolation: systemd hardening and least-privilege service accounts.
4. Data protection: TLS for transit, restricted file permissions at rest.
5. Monitoring: journald persistence, fail2ban, health checks, and audit trails.

## Storage Model

- Hot path: OS, service runtime state, and frequently accessed model assets.
- Cold path: backup sets, datasets, and large archives.
- Do not place high-random-read model workloads on degraded or slow media.

## Trust Boundaries

| Boundary | Trust Level | Controls |
|----------|-------------|----------|
| Internet to host | Untrusted | Firewall/security groups, TLS, auth |
| LAN to host | Low trust | Zero-trust allowlists, logging, rate limits |
| Proxy to local services | Internal | Loopback-only listeners |
| Admin to host | Verified only | SSH key auth, explicit privilege boundaries |
