# Yidelearn Label Studio Deployment Notes

This directory contains the deployment-specific helpers used for the
`https://yidelearn.com/label-studio/` installation.

The deployment uses fixed local accounts instead of self-registration or invite
links. Account credentials are stored on the server in:

```text
/opt/label-studio/config/users.tsv
```

The TSV file must contain two tab-separated columns:

```text
username	password
pku-coder001	CHANGE_ME
```

After editing `users.tsv`, run:

```bash
/opt/label-studio/config/sync_users.sh
systemctl restart label-studio
```

The first account in the file is made staff/superuser for maintenance. All
accounts are marked active and added to the first Label Studio organization.

The UI and API are customized to:

- disable public signup when `DISABLE_SIGNUP_WITHOUT_LINK=true`
- disable organization invite links when signup is disabled
- allow username-based login with `USE_USERNAME_FOR_LOGIN=true`
- support HTTPS reverse proxy CSRF handling via `CSRF_TRUSTED_ORIGINS`,
  `USE_X_FORWARDED_HOST`, and `SECURE_PROXY_SSL_HEADER`
- hide Enterprise-only or invitation-oriented UI affordances in Community
  Edition

## Local-only one-click deployment

Deployment is intentionally local-only. Do not add a GitHub Actions workflow or
CI/CD pipeline for this installation.

Run this from PowerShell on the local Windows machine:

```powershell
powershell -ExecutionPolicy Bypass -File D:\develop\label-studio\deploy\yidelearn\deploy-to-server.ps1
```

The script:

- runs local Python syntax checks
- installs frontend dependencies unless `-SkipInstall` is passed
- builds the Label Studio frontend unless `-SkipBuild` is passed
- verifies the built `main.js` no longer contains invitation or Enterprise-only
  UI phrases
- packages the changed source files and `web/dist/apps/labelstudio`
- uploads the package to `root@39.105.142.24`
- backs up the current server files under `/opt/label-studio/backups/`
- deploys the new source/build files
- syncs `/opt/label-studio/config/users.tsv`
- restarts `label-studio`
- checks the deployed frontend bundle

Useful variants:

```powershell
# Reuse already-installed node_modules
powershell -ExecutionPolicy Bypass -File D:\develop\label-studio\deploy\yidelearn\deploy-to-server.ps1 -SkipInstall

# Reuse an already-built web/dist/apps/labelstudio
powershell -ExecutionPolicy Bypass -File D:\develop\label-studio\deploy\yidelearn\deploy-to-server.ps1 -SkipInstall -SkipBuild
```
