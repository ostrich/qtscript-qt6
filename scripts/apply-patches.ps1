[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SourceDir,

    [string] $Repository = 'https://invent.kde.org/qt/qt/qtscript.git',

    [switch] $IncludePortedTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Run a native command with stderr merged into the success stream.
# Windows PowerShell 5.1 turns any native stderr line into a terminating
# error under $ErrorActionPreference = 'Stop' (plain 2>&1 does not help);
# pwsh 7 ignores native stderr entirely. This helper makes both behave the
# same and keeps $LASTEXITCODE as the single gatekeeper for success.
function Invoke-Native {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(ValueFromRemainingArguments)][object[]] $Arguments
    )
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @Arguments 2>&1
        $global:LASTEXITCODE = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $eap
    }
}

$sourceRevision = 'bcd7cae6215df8f1c8b45a338f3327da51edeaff'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git was not found on PATH.'
}

if (-not (Test-Path -LiteralPath (Join-Path $SourceDir '.git'))) {
    if (Test-Path -LiteralPath $SourceDir) {
        $existing = @(Get-ChildItem -LiteralPath $SourceDir -Force)
        if ($existing.Count -ne 0) {
            throw "SourceDir exists and is not empty: $SourceDir"
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $SourceDir -Parent) -Force | Out-Null
    }

    # Merge stderr so healthy progress chatter cannot terminate the run:
    # Windows PowerShell 5.1 treats every native stderr line as an error
    # under $ErrorActionPreference = 'Stop'; pwsh 7 does not.
    $cloneOutput = Invoke-Native git init --quiet $SourceDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host $cloneOutput
        throw "Unable to initialize KDE QtScript work tree at $SourceDir"
    }
    Invoke-Native git -C $SourceDir remote add origin $Repository | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to add KDE QtScript remote: $Repository" }
    Invoke-Native git -C $SourceDir fetch --quiet --depth 1 origin $sourceRevision | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to fetch KDE QtScript revision $sourceRevision" }
    Invoke-Native git -C $SourceDir checkout --quiet --detach FETCH_HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to check out KDE QtScript revision $sourceRevision" }
}

if (Test-Path -LiteralPath (Join-Path $SourceDir '.git\rebase-apply')) {
    throw "SourceDir has an interrupted git am session (.git/rebase-apply). Resolve or abort it first: $SourceDir"
}

$dirty = Invoke-Native git -C $SourceDir status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw "SourceDir is not a Git work tree: $SourceDir"
}
if ($dirty) {
    throw "The QtScript source tree has uncommitted changes: $SourceDir"
}

Invoke-Native git -C $SourceDir merge-base --is-ancestor $sourceRevision HEAD | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "SourceDir is not based on the pinned KDE QtScript revision: $sourceRevision"
}

function Apply-Patches {
    param([Parameter(Mandatory)][string] $PatchDirectory)

    $patches = @(Get-ChildItem -LiteralPath $PatchDirectory -Filter '*.patch' | Sort-Object Name)
    if ($patches.Count -eq 0) {
        throw "No patches were found in $PatchDirectory"
    }

    Write-Host "Applying $($patches.Count) patches from $PatchDirectory"
    $amOutput = Invoke-Native git -C $SourceDir `
        -c 'user.name=QtScript Qt 6 patch set' `
        -c 'user.email=qtscript-qt6@local.invalid' `
        am $patches.FullName
    if ($LASTEXITCODE -ne 0) {
        $null = Invoke-Native git -C $SourceDir am --abort
        Write-Host $amOutput
        throw "Failed to apply patches from $PatchDirectory"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'CMakeLists.txt'))) {
    $cmakeDir = Join-Path $repositoryRoot 'cmake'
    Copy-Item -LiteralPath (Join-Path $cmakeDir 'CMakeLists.txt') -Destination $SourceDir
    Copy-Item -LiteralPath (Join-Path $cmakeDir '.cmake.conf') -Destination $SourceDir
    Copy-Item -LiteralPath (Join-Path $cmakeDir 'src\CMakeLists.txt') -Destination (Join-Path $SourceDir 'src')
    Copy-Item -LiteralPath (Join-Path $cmakeDir 'src\script\CMakeLists.txt') -Destination (Join-Path $SourceDir 'src\script')
    Copy-Item -LiteralPath (Join-Path $cmakeDir 'src\scripttools\CMakeLists.txt') -Destination (Join-Path $SourceDir 'src\scripttools')
    Apply-Patches (Join-Path $repositoryRoot 'patches')
}

if ($IncludePortedTests -and
    -not (Test-Path -LiteralPath (Join-Path $SourceDir 'tests\CMakeLists.txt'))) {
    Apply-Patches (Join-Path $repositoryRoot 'patches\optional\tests')
}

Write-Host "Prepared QtScript source at $SourceDir"
