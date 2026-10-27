param(
 [string]$Report='C:\workspace\hi3798-node24-harness-armhf\reports\2026-10-27\harness-armhf',
 [string]$Repository='duskbreakmist/hi3798-node24-harness-armhf',
 [string]$Tag='dsh-0.2.1-rc.2-armhf-20261027'
)
$ErrorActionPreference='Stop'
$gh='C:\Program Files\GitHub CLI\gh.exe'
function Api([string]$Path,[string]$Method='GET',$Body=$null){
 $arguments=@('api','--method',$Method,$Path)
 if($null -ne $Body){
  $inputFile=Join-Path $Report 'github-api-input.json'
  [IO.File]::WriteAllText($inputFile,($Body|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
  $arguments+=@('--input',$inputFile)
 }
 $output=& $gh @arguments
 if($LASTEXITCODE -ne 0){throw "GitHub API failed: $Method $Path"}
 return ($output -join "`n"|ConvertFrom-Json -AsHashtable)
}
if(-not (Get-Content (Join-Path $Report 'installed-native-test.json') -Raw|ConvertFrom-Json).allPassed){throw 'Native integration failed'}
if(-not (Get-Content (Join-Path $Report 'web-startup.json') -Raw|ConvertFrom-Json).ready){throw 'HTTP startup failed'}
$names=@('harness-armhf-integration.tar.xz','harness-armhf-build-records.tar.xz','harness-install-inputs.tar.xz','SHA256SUMS')
foreach($name in $names){if(-not (Test-Path (Join-Path $Report $name))){throw "Missing asset: $name"}}
$files=[ordered]@{}
foreach($name in @('README.md','sources-manifest.json','builtin-arm32.patch','builtin-build-results.json','system-build-results.json','builtin-test.json','installed-native-test.json','armhf-integration.json','web-startup.json','web-startup.log','cli-help.txt','web-help.txt','bwrap-probe.txt','landlock-probe.txt','offline-npm-sha256.txt','board-final-state.txt','installation/package.json','installation/package-lock.json')){
 $files["harness-armhf/$name"]=Join-Path $Report $name
}
foreach($name in @('prepare-harness-builtin-arm32.py','prepare-harness-system-arm32.py','integrate-harness-armhf.py','deploy-harness-offline.py','test-harness-builtin.cjs','test-harness-install.mjs','test-harness-web.py','publish-harness-armhf.ps1')){
 $files["harness-armhf/scripts/$name"]=Join-Path $PSScriptRoot $name
}
$head=Api "repos/$Repository/git/ref/heads/main"
$sha=$head.object.sha
$base=Api "repos/$Repository/git/commits/$sha"
$entries=@()
foreach($item in $files.GetEnumerator()){
 $content=[IO.File]::ReadAllText($item.Value)
 if($content -match '(?i)(BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{30,})'){throw "Possible secret: $($item.Value)"}
 if($content -match '\?token=<redacted><redacted>)[A-Za-z0-9_-]{16,}'){throw "Unredacted startup token: $($item.Value)"}
 $entries+=@{path=$item.Key;mode='100644';type='blob';content=$content}
}
$tree=Api "repos/$Repository/git/trees" 'POST' @{base_tree=$base.tree.sha;tree=$entries}
$commit=Api "repos/$Repository/git/commits" 'POST' @{message='Add tested HI3798 Harness ARM32 adaptation and document unavailable kernel sandbox';tree=$tree.sha;parents=@($sha)}
if((Api "repos/$Repository/git/ref/heads/main").object.sha -ne $sha){throw 'Remote main changed; refusing overwrite'}
$null=Api "repos/$Repository/git/refs/heads/main" 'PATCH' @{sha=$commit.sha;force=$false}
$commit|ConvertTo-Json -Depth 20|Set-Content (Join-Path $Report 'published-commit.json') -Encoding utf8
$arguments=@('release','create',$Tag,'--repo',$Repository,'--target',$commit.sha,'--title','Harness 0.2.1-rc.2 ARM32 adaptation (kernel sandbox unavailable)','--notes-file',(Join-Path $Report 'release-notes.md'),'--draft','--prerelease')
$arguments+=$names|ForEach-Object{Join-Path $Report $_}
& $gh @arguments
if($LASTEXITCODE -ne 0){throw 'Draft release upload failed'}
$release=(Api "repos/$Repository/releases?per_page=50")|Where-Object{$_.tag_name -eq $Tag}|Select-Object -First 1
if(-not $release){throw 'Missing draft release'}
foreach($name in $names){
 $asset=$release.assets|Where-Object{$_.name -eq $name}|Select-Object -First 1
 $file=Get-Item (Join-Path $Report $name)
 $digest=(Get-FileHash -Algorithm SHA256 $file.FullName).Hash.ToLowerInvariant()
 if(-not $asset -or $asset.size -ne $file.Length -or $asset.digest -ne "sha256:$digest"){throw "Asset mismatch: $name"}
}
$release=Api "repos/$Repository/releases/$($release.id)" 'PATCH' @{draft=$false;prerelease=$true;make_latest='false';target_commitish=$commit.sha}
$release|ConvertTo-Json -Depth 30|Set-Content (Join-Path $Report 'published-release.json') -Encoding utf8
$release.html_url
