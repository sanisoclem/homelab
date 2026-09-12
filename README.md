# homelab

## Prerequisites

 - `tofu`
 - `kubectl`
 - `helm`
 - `talosctl`
 - `task`
 - `openssl` 
 - `python3` 

## Setup


### On Proxmox Host


1. Claude says I need this. Looks like enabling storage options?

```bash
pvesm set local --content iso,vztmpl,backup,snippets
```

1. Configure ssh keys, will need to enter root pass

```bash
ssh-copy-id root@pve
```

1. Create API Token in proxmox

### Network 

Need to assign static IPs to the VM (proxmox also requires a static IP). My DHCP range is `10.7.X.100-254`, so anything below 100 is static in all VLANs. 

### Github

1. Create an OAuth App. This will be used by ArgoCD and Grafana. 

| service | callback URL |
|---|---|
| Argo CD | `https://cd.<zone>/api/dex/callback` |
| Grafana | `https://grafana.<zone>/login/github` |

Turn off short-lived tokens. It seems to be turned on by default for new apps now.

1. Create a PAT per gitops repo 

1. Create a classic PAT with `read:packages`, this will be used by argocd to pull images from ghcr.

1. Create a Cloudflare API Token for each zone (`Zone:Read` and `Zone:DNS:Edit`). This is used to create DNS records for the LB and for cert-manager challenges.

1. Create TrueNAS API key, MinIO (hosted in truenas)

## Provisioning

```bash
task up
```

This also bootstraps all the gitops repos and seeds zitadel. So all gitops repos must be pushed, especially platform repo so zitadel can start and be seeded within the time limit.

## Destroying

```bash
task destroy
```

This destroys all VMs. Postgres data will be destroyed (?) but is backed up to the NAS.
