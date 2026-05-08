# Network Topology - Reference Design

## Objective

Provide a reusable network model for Debian 13 hosts running OmIronClaw in either bare-metal LAN or VPS environments.

## Logical Layout

```text
Internet/WAN
   |
Gateway or Cloud Security Group
   |
Management Zone (<MGMT_SUBNET>)
   |-- Debian Host A (<SERVER_HOSTNAME>, <SERVER_IP>)
   |-- Optional Auditor Host (<AUDIT_HOSTNAME>, <AUDIT_IP>)
   |-- Optional Admin Workstation (<ADMIN_HOSTNAME>, <ADMIN_IP>)
```

## Baseline Exposure Policy

| Port | Protocol | Service | Source | Policy |
|------|----------|---------|--------|--------|
| 22 | TCP | SSH | <ADMIN_ALLOWED_SUBNET> | Allow (rate-limited) |
| 80 | TCP | HTTP | <LAN_SUBNET> or optional public | Allow (redirect only) |
| 443 | TCP | HTTPS | <LAN_SUBNET> or optional public | Allow |
| 5353 | UDP | mDNS (optional) | <LAN_SUBNET> | Allow only if needed |
| * | * | Any other inbound | Any | Drop |

## Outbound Policy (Recommended)

| Destination | Protocol | Reason |
|-------------|----------|--------|
| DNS resolvers | TCP/UDP 53, TCP 853 | Name resolution / DoT |
| NTP | UDP 123 | Time synchronization |
| Package and model registries | TCP 443 | Updates and model pulls |
| Optional managed hosts | TCP 22/2222 | Automation and maintenance |

## Deployment Profiles

### LAN Profile
- Local reverse proxy and AI APIs restricted to LAN clients.
- SSH restricted to admin hosts.
- Optional local channels (Telegram/WhatsApp) through outbound HTTPS.

### VPS Profile
- Use provider firewall/security groups as first boundary.
- Expose only 22 and 443 publicly unless strict private networking is configured.
- Enforce API auth and TLS at the proxy layer.

## Validation Checklist

- Verify only intended ports are reachable from an external host.
- Verify firewall default policy is deny/drop for inbound.
- Verify Ollama and OpenClaw bind to loopback unless intentionally exposed via proxy.
- Verify audit logs capture denied traffic and authentication events.
