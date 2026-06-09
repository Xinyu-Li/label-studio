param(
  [string]$Server = "root@39.105.142.24",
  [string]$KeyFile = "$env:USERPROFILE\.ssh\flora_beijing.pem",
  [string]$LocalUsersFile = "",
  [string]$BaseRef = "1.23.0",
  [switch]$SkipInstall,
  [switch]$SkipBuild,
  [switch]$SkipDeploy,
  [switch]$SkipRemoteVerify
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
$WebRoot = Join-Path $RepoRoot "web"
$DistRoot = Join-Path $WebRoot "dist\apps\labelstudio"
$Stamp = Get-Date -Format "yyyyMMddHHmmss"
$WorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) "label-studio-deploy-$Stamp"
$Archive = Join-Path ([System.IO.Path]::GetTempPath()) "label-studio-deploy-$Stamp.tar.gz"
$RemoteArchive = "/tmp/label-studio-deploy-$Stamp.tar.gz"
$RemoteScript = "/tmp/label-studio-deploy-$Stamp.sh"
$RemoteUsersFile = "/tmp/label-studio-users-$Stamp.tsv"

if ([string]::IsNullOrWhiteSpace($LocalUsersFile)) {
  $LocalUsersFile = Join-Path $ScriptDir "config\users.tsv"
}

$RuntimePackageFiles = @(
  "label_studio/core/settings/base.py",
  "label_studio/data_manager/prepare_params.py",
  "label_studio/organizations/api.py",
  "label_studio/users/templates/users/new-ui/user_base.html",
  "label_studio/users/templates/users/new-ui/user_tips.html",
  "label_studio/users/views.py"
)

$HiddenPhrases = @(
  "Invite Members",
  "Add Members",
  "Invite members",
  "Label Studio Enterprise",
  "Enterprise only",
  "Available on Label Studio Enterprise",
  "goenterprise"
)

function Invoke-Checked {
  param(
    [string]$Title,
    [scriptblock]$Script
  )
  Write-Host ""
  Write-Host "==> $Title"
  & $Script
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

function Copy-RepoFile {
  param([string]$RelativePath)
  $src = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path $src)) {
    Write-Warning "Skipping missing file: $RelativePath"
    return
  }
  if ((Get-Item $src).PSIsContainer) {
    return
  }
  $dst = Join-Path $WorkRoot $RelativePath
  New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

Push-Location $RepoRoot
try {
  Invoke-Checked "Checking prerequisites" {
    Require-Command git
    Require-Command ssh
    Require-Command scp
    Require-Command tar
    Require-Command python
    Require-Command yarn
    if (-not (Test-Path $KeyFile)) {
      throw "SSH key not found: $KeyFile"
    }
    if (Test-Path $LocalUsersFile) {
      Write-Host "local users file will be uploaded: $LocalUsersFile"
    } else {
      Write-Host "no local users.tsv found; server users.tsv will be kept"
    }
    git rev-parse --verify $BaseRef | Out-Null
  }

  Invoke-Checked "Running local Python syntax checks" {
    $pyFiles = @(
      "label_studio/core/settings/base.py",
      "label_studio/data_manager/prepare_params.py",
      "label_studio/organizations/api.py",
      "label_studio/users/views.py",
      "deploy/yidelearn/seed_users.py"
    )
    foreach ($file in $pyFiles) {
      python -m py_compile (Join-Path $RepoRoot $file)
      Write-Host "ok $file"
    }
  }

  if (-not $SkipInstall) {
    Invoke-Checked "Installing frontend dependencies" {
      Push-Location $WebRoot
      try {
        yarn install --frozen-lockfile --network-timeout 600000
      } finally {
        Pop-Location
      }
    }
  }

  if (-not $SkipBuild) {
    Invoke-Checked "Building Label Studio frontend" {
      Push-Location $WebRoot
      try {
        $env:NODE_ENV = "production"
        yarn ls:build
      } finally {
        Pop-Location
      }
    }
  }

  Invoke-Checked "Checking local frontend bundle" {
    $mainJs = Join-Path $DistRoot "main.js"
    if (-not (Test-Path $mainJs)) {
      throw "Frontend bundle missing: $mainJs"
    }
    $bundle = Get-Content $mainJs -Raw
    $matches = $HiddenPhrases | Where-Object { $bundle.Contains($_) }
    if ($matches.Count -gt 0) {
      throw "Hidden UI phrases still present in main.js: $($matches -join ', ')"
    }
    Write-Host "ok main.js does not contain hidden invitation/Enterprise phrases"
  }

  Invoke-Checked "Creating deployment archive" {
    if (Test-Path $WorkRoot) {
      Remove-Item -LiteralPath $WorkRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $WorkRoot | Out-Null

    $changed = @(git diff --name-only $BaseRef)
    $untracked = @(git ls-files --others --exclude-standard deploy/yidelearn)
    $files = @($changed + $untracked) |
      Where-Object { $_ -and (-not $_.StartsWith(".github/")) } |
      Sort-Object -Unique

    foreach ($file in $files) {
      Copy-RepoFile $file
    }

    $distDst = Join-Path $WorkRoot "web\dist\apps\labelstudio"
    New-Item -ItemType Directory -Path (Split-Path $distDst -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $DistRoot -Destination $distDst -Recurse -Force

    if (Test-Path $Archive) {
      Remove-Item -LiteralPath $Archive -Force
    }
    tar -czf $Archive -C $WorkRoot .
    Write-Host "archive $Archive"
  }

  if ($SkipDeploy) {
    Write-Host ""
    Write-Host "Local checks and packaging complete. Deployment skipped."
    Write-Host "Archive: $Archive"
    return
  }

  $remoteShell = @"
#!/usr/bin/env bash
set -euo pipefail

pkg="$RemoteArchive"
users_file="$RemoteUsersFile"
source_root="/opt/label-studio/app/source"
site_root="/opt/label-studio/venv/lib/python3.12/site-packages"
config_root="/opt/label-studio/config"
backup="/opt/label-studio/backups/yidelearn-custom-before-$Stamp.tar.gz"

test -s "`$pkg"
mkdir -p /opt/label-studio/backups
cd "`$source_root"

tar -czf "`$backup" \
  label_studio/core/settings/base.py \
  label_studio/data_manager/prepare_params.py \
  label_studio/organizations/api.py \
  label_studio/users/templates/users/new-ui/user_base.html \
  label_studio/users/templates/users/new-ui/user_tips.html \
  label_studio/users/views.py \
  web/apps/labelstudio/src/pages/CreateProject/Config/TemplatesList.jsx \
  web/apps/labelstudio/src/pages/CreateProject/CreateProject.jsx \
  web/apps/labelstudio/src/pages/CreateProject/Import/Import.jsx \
  web/apps/labelstudio/src/pages/ExportPage/ExportPage.jsx \
  web/apps/labelstudio/src/pages/Home/HomePage.tsx \
  web/apps/labelstudio/src/pages/Organization/PeoplePage/PeoplePage.jsx \
  web/apps/labelstudio/src/pages/Settings/GeneralSettings.jsx \
  web/apps/labelstudio/src/pages/Settings/StorageSettings/providers/index.ts \
  web/libs/datamanager/src/components/Common/FieldsButton.jsx \
  web/libs/datamanager/src/components/DataManager/Toolbar/ActionsButton.jsx \
  web/libs/datamanager/src/components/DataManager/Toolbar/OrderButton.jsx \
  web/libs/datamanager/src/components/Filters/FilterLine/FilterLine.jsx \
  web/libs/datamanager/src/components/MainView/DataView/Table.jsx \
  web/dist/apps/labelstudio

tar -xzf "`$pkg" -C "`$source_root"

cp "`$source_root/deploy/yidelearn/seed_users.py" "`$config_root/seed_users.py"
cp "`$source_root/deploy/yidelearn/sync_users.sh" "`$config_root/sync_users.sh"
chmod 600 "`$config_root/seed_users.py"
chmod 700 "`$config_root/sync_users.sh"

if [ -s "`$users_file" ]; then
  cp "`$users_file" "`$config_root/users.tsv"
  chmod 600 "`$config_root/users.tsv"
fi

for f in $($RuntimePackageFiles -join ' '); do
  cp "`$source_root/`$f" "`$site_root/`$f"
done

"`$config_root/sync_users.sh"
systemctl restart label-studio
sleep 4
systemctl is-active label-studio
echo "backup=`$backup"
"@

  $remoteScriptLocal = Join-Path ([System.IO.Path]::GetTempPath()) "label-studio-deploy-$Stamp.sh"
  Set-Content -Path $remoteScriptLocal -Value $remoteShell -Encoding UTF8

  Invoke-Checked "Uploading archive and remote deploy script" {
    scp -i $KeyFile -o StrictHostKeyChecking=accept-new $Archive "${Server}:$RemoteArchive"
    scp -i $KeyFile -o StrictHostKeyChecking=accept-new $remoteScriptLocal "${Server}:$RemoteScript"
    if (Test-Path $LocalUsersFile) {
      scp -i $KeyFile -o StrictHostKeyChecking=accept-new $LocalUsersFile "${Server}:$RemoteUsersFile"
    }
  }

  Invoke-Checked "Deploying on server" {
    ssh -i $KeyFile -o StrictHostKeyChecking=accept-new $Server "bash $RemoteScript"
  }

  if (-not $SkipRemoteVerify) {
    Invoke-Checked "Running remote smoke checks" {
      $verify = @"
import requests

url = 'https://yidelearn.com/label-studio/react-app/main.js?v=none'
r = requests.get(url, timeout=25)
r.raise_for_status()
hidden = $($HiddenPhrases | ConvertTo-Json -Compress)
found = [phrase for phrase in hidden if phrase in r.text]
print('main_js_status', r.status_code, r.headers.get('content-type'), len(r.text))
print('hidden_phrases_found', found)
if found:
    raise SystemExit(2)
"@
      $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($verify))
      ssh -i $KeyFile -o StrictHostKeyChecking=accept-new $Server "/opt/label-studio/venv/bin/python -c 'import base64,sys; exec(base64.b64decode(sys.argv[1]))' $encoded"
    }
  }

  Write-Host ""
  Write-Host "Deploy complete: https://yidelearn.com/label-studio/"
} finally {
  Pop-Location
}
