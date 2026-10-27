param(
    [string]$Report = 'C:\workspace\hi3798-node24-harness-armhf\reports\2026-10-26\node24-armhf',
    [string]$Repository = 'duskbreakmist/hi3798-node24-harness-armhf',
    [string]$Tag = 'node-v24.22.1-armhf-20261027'
)
$ErrorActionPreference = 'Stop'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
function Invoke-GhApi([string]$Path, [string]$Method = 'GET', $Body = $null) {
    $ghArgs = @('api', '--method', $Method, $Path)
    if ($null -ne $Body) {
        $inputFile = Join-Path $Report 'github-api-input.json'
        [IO.File]::WriteAllText($inputFile, ($Body | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
        $ghArgs += @('--input', $inputFile)
    }
    $result = & $gh @ghArgs
    if ($LASTEXITCODE -ne 0) { throw "GitHub API failed: $Method $Path" }
    return ($result -join "`n" | ConvertFrom-Json -AsHashtable)
}
$validation = Get-Content (Join-Path $Report 'board-smoke.json') -Raw | ConvertFrom-Json
if (-not $validation.allPassed) { throw 'Board smoke tests did not pass; refusing success release' }
$assetNames = @('node-v24.22.1-linux-armv7l-hi3798.tar.xz', 'node-v24.22.1-armhf-native-addons.tar.xz', 'node-v24.22.1-armhf-build-records.tar.xz', 'SHA256SUMS')
foreach ($name in $assetNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $Report $name))) { throw "Missing release asset: $name" }
}
$files = [ordered]@{
    'node24-armhf/README.md' = (Join-Path $Report 'README.md')
    'node24-armhf/source-manifest.json' = (Join-Path $Report 'source-manifest.json')
    'node24-armhf/validation/board-smoke.json' = (Join-Path $Report 'board-smoke.json')
    'node24-armhf/validation/board-runtime.txt' = (Join-Path $Report 'board-runtime.txt')
    'node24-armhf/validation/board-native-candidates.json' = (Join-Path $Report 'board-native-candidates.json')
    'node24-armhf/validation/board-https.json' = (Join-Path $Report 'board-https.json')
    'node24-armhf/validation/board-npm-pack.json' = (Join-Path $Report 'board-npm-pack.json')
    'node24-armhf/validation/board-binary-hashes.json' = (Join-Path $Report 'board-binary-hashes.json')
    'node24-armhf/validation/deployment-summary.json' = (Join-Path $Report 'deployment-summary.json')
    'node24-armhf/native-server-build-results.json' = (Join-Path $Report 'native-server-build-results.json')
    'node24-armhf/build-packages.tsv' = (Join-Path $Report 'build-packages.tsv')
    'node24-armhf/dsh-dependencies/README.md' = (Join-Path $Report 'dsh-dependencies/README.md')
    'node24-armhf/dsh-dependencies/package.json' = (Join-Path $Report 'dsh-dependencies/package.json')
    'node24-armhf/dsh-dependencies/package-lock.json' = (Join-Path $Report 'dsh-dependencies/package-lock.json')
    'node24-armhf/dsh-dependencies/koffi__3.3.4.json' = (Join-Path $Report 'dsh-dependencies/koffi__3.3.4.json')
    'node24-armhf/dsh-dependencies/@koromix__koffi-linux-arm__3.3.4.json' = (Join-Path $Report 'dsh-dependencies/@koromix__koffi-linux-arm__3.3.4.json')
    'node24-armhf/dsh-dependencies/prebuilt-candidates.json' = (Join-Path $Report 'dsh-dependencies/prebuilt-candidates.json')
    'node24-armhf/dsh-dependencies/native-build-results.json' = (Join-Path $Report 'dsh-dependencies/native-build-results.json')
    'node24-armhf/dsh-dependencies/board-ripgrep.txt' = (Join-Path $Report 'dsh-dependencies/board-ripgrep.txt')
    'node24-armhf/dsh-dependencies/board-bwrap-probe.txt' = (Join-Path $Report 'dsh-dependencies/board-bwrap-probe.txt')
}
foreach ($name in @('build-node24-armhf.sh','build-node24-server.sh','proot-no-statx.c','zlib-arm32-crc-flags.patch','v8-arm32-dependent-template.patch','smoke-test.mjs','test-native-candidates.mjs','deploy-node24.py','publish-node24.ps1')) {
    $files["node24-armhf/scripts/$name"] = Join-Path $PSScriptRoot $name
}
$head = Invoke-GhApi "repos/$Repository/git/ref/heads/main"
$baseSha = $head.object.sha
$base = Invoke-GhApi "repos/$Repository/git/commits/$baseSha"
$entries = @()
foreach ($entry in $files.GetEnumerator()) {
    $content = [IO.File]::ReadAllText($entry.Value)
    if ($content -match '(?i)(BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{30,})') { throw "Possible secret: $($entry.Value)" }
    $entries += @{path=$entry.Key;mode='100644';type='blob';content=$content}
}
$tree = Invoke-GhApi "repos/$Repository/git/trees" 'POST' @{base_tree=$base.tree.sha;tree=$entries}
$commit = Invoke-GhApi "repos/$Repository/git/commits" 'POST' @{message='Add HI3798 Node 24 armhf build, board validation and Harness dependency audit';tree=$tree.sha;parents=@($baseSha)}
$latest = Invoke-GhApi "repos/$Repository/git/ref/heads/main"
if ($latest.object.sha -ne $baseSha) { throw 'Remote main changed; do not overwrite it' }
$null = Invoke-GhApi "repos/$Repository/git/refs/heads/main" 'PATCH' @{sha=$commit.sha;force=$false}
$commit | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $Report 'published-commit.json') -Encoding utf8
$releaseArgs = @('release','create',$Tag,'--repo',$Repository,'--target',$commit.sha,'--title','Node 24.22.1 for HI3798 Debian 12 armhf','--notes-file',(Join-Path $Report 'release-notes.md'),'--draft')
$releaseArgs += $assetNames | ForEach-Object { Join-Path $Report $_ }
& $gh @releaseArgs
if ($LASTEXITCODE -ne 0) { throw 'Draft release creation/upload failed' }
$releases = Invoke-GhApi "repos/$Repository/releases?per_page=50"
$release = $releases | Where-Object { $_.tag_name -eq $Tag } | Select-Object -First 1
if (-not $release) { throw 'Draft release missing' }
foreach ($name in $assetNames) {
    $asset = $release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    $local = Get-Item -LiteralPath (Join-Path $Report $name)
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $local.FullName).Hash.ToLowerInvariant()
    if (-not $asset -or $asset.size -ne $local.Length -or $asset.digest -ne "sha256:$hash") { throw "Uploaded asset mismatch: $name" }
}
$release = Invoke-GhApi "repos/$Repository/releases/$($release.id)" 'PATCH' @{draft=$false;prerelease=$false;make_latest='false';tag_name=$Tag;target_commitish=$commit.sha}
$release | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $Report 'published-release.json') -Encoding utf8
Write-Output $release.html_url
