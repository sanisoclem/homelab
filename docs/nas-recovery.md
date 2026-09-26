# NAS recovery

For when the NAS or its pool is gone. If only the cluster is gone, `task up` is enough.

Everything the cluster restores (databases, block-backed volumes) comes from rustfs, so rustfs's dataset goes back first. Names and addresses below are `.env` keys.

## You need

- your latest manual TrueNAS config backup, saved with the secret seed

From the password manager:

- homelab `.env`
- Storj access key and secret key (the TrueNAS `Storj` cloud credential)
- Storj encryption password (`TRUECLOUD_PASSWORD`); it decrypts every backup below

## What Storj holds

The TrueNAS config lists every TrueCloud task; the ones the cluster depends on:

| Dataset | Storj bucket:folder | Contents |
|---|---|---|
| `NAS_S3_DATASET` | its own task, made by hand | rustfs: CNPG base backups and WAL, VolSync restic repos |
| `TF_VAR_nas_dataset`/apps | `STORJ_BUCKET`:/`<dataset without pool>` | app config, Paperless documents |
| each leaf of `NAS_SERVICE_DATASET` | `STORJ_BUCKET`:/`<dataset without pool>` | knowledge and the other service datasets |
| datasets under `NAS_USER_DATASET` | their own tasks, made by hand | personal files, Emby library, Immich |

Not recoverable by design: `NAS_SCRATCH_DATASET`, datasets without a TrueCloud task, and anything on `block-transient`.

## Steps

1. Install TrueNAS 25.04 or newer at `TF_VAR_nas_host`, and create the pool named in `TF_VAR_nas_dataset`.

2. System → General Settings → Manage Configuration → Upload Config, with your latest config backup. This brings back users, shares, the iSCSI portal, the API key in `.env`, the Storj credential, and the backup and snapshot tasks. The NAS reboots.

3. Create every dataset a TrueCloud task points at, same names.

4. Data Protection → TrueCloud Backup → each task → Restore → latest, into its own dataset. `NAS_S3_DATASET` first, then the cluster's apps dataset, then the rest.

5. Reinstall the RustFS app: API port from `TF_VAR_s3_endpoint`, data host path `/mnt/<NAS_S3_DATASET>`, run as `568:568`, access and secret key from `TF_VAR_s3_access_key` / `TF_VAR_s3_secret_key`.

6. Rebuild the cluster. The old one cannot flush to a NAS that is gone:

   ```bash
   SKIP_FLUSH=1 task destroy
   task up
   ```

7. Check:
   - `kubectl get clusters.postgresql.cnpg.io -A`: every cluster healthy.
   - `kubectl get replicationdestinations -A`: every one has a `lastSyncTime`.
   - Paperless shows its documents, Emby its users and watch state, Zitadel lets you log in.
   - Run each TrueCloud task once from the UI.

## Drill

Once a year, restore the apps backup into `NAS_SCRATCH_DATASET` on a laptop and open a few files:

```bash
export AWS_ACCESS_KEY_ID=<storj access key> AWS_SECRET_ACCESS_KEY=<storj secret key>
export RESTIC_PASSWORD=<storj encryption password>
restic -r "s3:https://gateway.storjshare.io/$STORJ_BUCKET/k8s/apps" restore latest --target ./k8s-apps
```
