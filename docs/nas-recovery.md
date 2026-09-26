# NAS recovery

For when the NAS or pool `main` is gone. If only the cluster is gone, `task run` is enough.

Everything the cluster restores (databases, block-backed volumes) comes from rustfs, so rustfs's dataset goes back first.

## You need

- your latest manual TrueNAS config backup, saved with the secret seed

From the password manager:

- homelab `.env`
- Storj access key and secret key (the TrueNAS `Storj` cloud credential)
- Storj encryption password (`TRUECLOUD_PASSWORD` in `.env`); it decrypts every backup below

## What Storj holds

| Storj bucket:folder | Dataset | Contents |
|---|---|---|
| `s3-backups:/` | `main/k8s/s3-backups` | rustfs: CNPG base backups and WAL, VolSync restic repos |
| `usr-backup:/k8s-apps` | `main/k8s/apps` | app config, Paperless documents |
| `usr-backup:/svc/<name>` | `main/svc/<name>` | knowledge, proxy-manager, overseerr, portainer |
| `usr-backup:/mel`, `/joelle`, `/shared`, `/emby`, `/immich-db`, `/immich-files` | `main/usr/...` | personal files, Emby library, Immich |
| `sys-backup:/` | `main/svc` | history from before the per-dataset tasks |

Not recoverable by design: `main/usr/plex`, `main/usr/scratch`, and anything on `block-transient`.

## Steps

1. Install TrueNAS 25.04 or newer on `10.11.7.30` and create pool `main`.

2. System → General Settings → Manage Configuration → Upload Config, with your latest config backup. This brings back users, shares, the iSCSI portal, the API key in `.env`, the Storj credential, and the backup and snapshot tasks. The NAS reboots.

3. Create the datasets in the table, same names, then run `task nas:apply` for the cluster's own datasets.

4. Data Protection → TrueCloud Backup → each task → Restore → latest, into its own dataset. In this order: `s3-backups`, `k8s/apps`, `svc/*`, `usr/*`.

5. Reinstall the RustFS app: API port `30292`, web port `30293`, data host path `/mnt/main/k8s/s3-backups`, run as `568:568`, access and secret key from `TF_VAR_s3_access_key` / `TF_VAR_s3_secret_key`.

6. Rebuild the cluster. The old one cannot flush to a NAS that is gone:

   ```bash
   SKIP_FLUSH=1 task destroy
   task run
   ```

7. Check:
   - `kubectl get clusters.postgresql.cnpg.io -A`: every cluster healthy.
   - `kubectl get replicationdestinations -A`: every one has a `lastSyncTime`.
   - Paperless shows its documents, Emby its users and watch state, Zitadel lets you log in.
   - Run each TrueCloud task once from the UI.

## Drill

Once a year, restore `usr-backup:/k8s-apps` into `main/usr/scratch` on a laptop and open a few files:

```bash
export AWS_ACCESS_KEY_ID=<storj access key> AWS_SECRET_ACCESS_KEY=<storj secret key>
export RESTIC_PASSWORD=<storj encryption password>
restic -r s3:https://gateway.storjshare.io/usr-backup/k8s-apps restore latest --target ./k8s-apps
```
