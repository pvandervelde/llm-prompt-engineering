#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Self-contained test harness for the container-spawn primitives in
    tools/workflow/workflow.ps1 (Start-IsolationContainer,
    Get-IsolationContainerRuntime, Get-IsolationPlainImageRef --
    workflow/isolation.md sections 3/10, piece 4 of the run-isolated
    implementation).
.DESCRIPTION
    Unlike tools/workflow/test/test-workflow.ps1, this REQUIRES a real
    container runtime (Podman or Docker) and actually spawns containers --
    kept as its own file, not run as part of the main engine suite, so
    that suite stays dependency-free. Mirrors test-container-spawn.sh
    scenario-for-scenario.

    Observed flaky once (2026-10-24) under many rapid back-to-back `docker
    run` invocations: scenario 06 failed with a Windows process-start
    error code (not anything from inside the container), passed again on
    an immediate re-run with no code change. Same class of host-resource
    flake as tools/ai-bootstrap/test/test-install.*'s documented one, not
    a logic bug -- re-run once before treating a failure here as real.
.EXAMPLE
    pwsh ./tools/workflow/isolation/test/test-container-spawn.ps1
#>

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../../..")).Path
$WorkflowPs1 = Join-Path $RepoRoot "tools/workflow/workflow.ps1"
$GitWrapper = Join-Path $RepoRoot "tools/workflow/isolation/git-wrapper.sh"

$script:PassCount = 0
$script:FailCount = 0
$script:FailedNames = @()

function Pass([string]$Name) {
    $script:PassCount++
    Write-Host "  PASS: $Name"
}

function Fail2([string]$Name, [string]$Detail) {
    $script:FailCount++
    $script:FailedNames += $Name
    Write-Host "  FAIL: $Name -- $Detail"
}

function Assert-Eq([string]$Name, $Expected, $Actual) {
    if ("$Expected" -eq "$Actual") { Pass $Name } else { Fail2 $Name "expected [$Expected], got [$Actual]" }
}

function Assert-Contains([string]$Name, [string]$Haystack, [string]$Needle) {
    if ($Haystack.Contains($Needle)) { Pass $Name } else { Fail2 $Name "expected output to contain [$Needle], got [$Haystack]" }
}

# Sets up a fresh scratch git repo at $1, with the git wrapper copied into
# it at the same relative path Start-IsolationContainer expects to find it.
function New-Scratch([string]$Dir) {
    if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
    New-Item -ItemType Directory -Path "$Dir/tools/workflow/isolation" -Force | Out-Null
    Copy-Item $GitWrapper "$Dir/tools/workflow/isolation/git-wrapper.sh"
    Push-Location $Dir
    try {
        git init -q
        git config user.email test@test.com
        git config user.name test
        "initial" | Set-Content README.md
        git add -A
        git commit -q -m init
    } finally {
        Pop-Location
    }
}

# Runs an expression in a fresh child pwsh process, after dot-sourcing
# workflow.ps1 with the test-only "__noop__" sentinel (defines every
# function without dispatching a real command). A child process, not
# direct dot-sourcing in this test's own process, because Fail calls exit
# -- which would kill this test runner itself if an error-path call ran
# in-process. Mirrors Invoke-Wf's reason for shelling out, in
# test-workflow.ps1.
function Invoke-IsolationFn([string]$Expr) {
    $cmd = ". '$WorkflowPs1' -Command '__noop__'; $Expr"
    $out = & pwsh -NoProfile -Command $cmd 2>&1
    return [PSCustomObject]@{ Output = ($out -join "`n"); ExitCode = $LASTEXITCODE }
}

Write-Host "=== tools/workflow/isolation/test/test-container-spawn.ps1 ==="
Write-Host ""

if (-not (Get-Command docker -ErrorAction SilentlyContinue) -and -not (Get-Command podman -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: neither docker nor podman is installed on this host -- nothing to test"
    exit 0
}

Write-Host "Image spec translation"

$r = Invoke-IsolationFn "Get-IsolationPlainImageRef -Spec 'image:rust:1-slim'"
Assert-Eq "01 image: spec strips to a plain reference" "rust:1-slim" $r.Output.Trim()

$r = Invoke-IsolationFn "Get-IsolationPlainImageRef -Spec 'build:Dockerfile:.'"
Assert-Eq "02 build: spec is refused (not yet implemented), not silently mishandled" "1" $r.ExitCode
Assert-Contains "03 the refusal names what's missing" $r.Output "not yet implemented"

$r = Invoke-IsolationFn "Get-IsolationPlainImageRef -Spec 'garbage'"
Assert-Eq "04 an unrecognized spec is refused" "1" $r.ExitCode

Write-Host ""
Write-Host "Container spawn (real container, requires docker/podman)"

# Dot-source directly from here on -- Start-IsolationContainer's success
# path never calls Fail (its exit code comes from the spawned container
# process, not PowerShell's own exit), so it's safe in-process as long as
# the runtime and wrapper file both exist, which this test ensures.
. $WorkflowPs1 -Command "__noop__"

$scr = Join-Path $env:TEMP "wf-container-spawn-$(Get-Random)"
New-Scratch $scr

$r = Start-IsolationContainer -Root $scr -Image "alpine/git:latest" -Command "git status --porcelain"
Assert-Eq "05 a basic spawn against a real scratch repo succeeds" "0" $r.ExitCode

$r = Start-IsolationContainer -Root $scr -Image "alpine/git:latest" -Command "which git"
Assert-Contains "06 the git wrapper is on PATH ahead of the real binary" $r.Output "/usr/local/bin/git"

$r = Start-IsolationContainer -Root $scr -Image "alpine/git:latest" -Command "git push"
Assert-Eq "07 a denied git command's exit code propagates out" "1" $r.ExitCode
Assert-Contains "08 the denial message is visible in the spawn's output" $r.Output "not permitted"

$r = Start-IsolationContainer -Root $scr -Image "alpine/git:latest" -Command "git log --oneline -1"
Assert-Eq "09 an allowed read-only command still succeeds" "0" $r.ExitCode

$sentinel = "isolation-spawn-test-$(Get-Random)"
Start-IsolationContainer -Root $scr -Image "alpine/git:latest" -Command "echo '$sentinel' > /workspace/written-from-container.txt" | Out-Null
$writtenPath = Join-Path $scr "written-from-container.txt"
if ((Test-Path $writtenPath) -and (Get-Content $writtenPath -Raw).Contains($sentinel)) {
    Pass "10 the workspace mount is really read-write against the scratch repo"
} else {
    Fail2 "10 the workspace mount is really read-write against the scratch repo" "file not found or content mismatch"
}

$r = Start-IsolationContainer -Root $scr -Image "alpine/git:latest" -Command "cat /etc/hostname 2>&1; ls /root 2>&1 | head -1"
Assert-Eq "11 a plain-filesystem command inside the container still succeeds (confinement is about host paths, not the container's own rootfs)" "0" $r.ExitCode

Write-Host ""
Write-Host "Network policy (SNI-filtered proxy sidecar, section 9 -- real network traffic, slower)"

$r = Start-IsolationContainer -Root $scr -Image "curlimages/curl:latest" -Command "curl -sS -m 15 -o /dev/null -w 'HTTP %{http_code}' https://crates.io/" -Toolchain "rust"
Assert-Eq "12 an allowed SNI (crates.io, via the rust toolchain allowlist) is reachable through the proxy" "0" $r.ExitCode
Assert-Contains "13 a reached allowed host returns a real HTTP response, not a proxy error page" $r.Output "HTTP"

$r = Start-IsolationContainer -Root $scr -Image "curlimages/curl:latest" -Command "curl -sS -m 15 -o /dev/null -w 'HTTP %{http_code}' https://www.wikipedia.org/" -Toolchain "rust"
if ($r.ExitCode -ne 0) {
    Pass "14 a disallowed SNI fails at the TLS layer (terminated after the peek), not with an HTTP response"
} else {
    Fail2 "14 a disallowed SNI fails at the TLS layer (terminated after the peek), not with an HTTP response" "curl exited 0: $($r.Output)"
}

$r = Start-IsolationContainer -Root $scr -Image "curlimages/curl:latest" -Command "curl -sS -m 10 --noproxy '*' -o /dev/null -w 'HTTP %{http_code}' https://crates.io/ 2>&1" -Toolchain "rust"
Assert-Contains "15 bypassing the proxy entirely still fails outright (no route exists, not just non-compliance)" $r.Output "ould not resolve host"

# Plain HTTP is a separate code path from the ssl_bump/CONNECT logic
# above (section 9) -- found (2026-10-23) that without its own dstdomain
# gate, ANY plain-HTTP destination was allowed through unfiltered.
$r = Start-IsolationContainer -Root $scr -Image "curlimages/curl:latest" -Command "curl -sS -m 10 -o /dev/null -w 'HTTP %{http_code}' http://deb.debian.org/debian/dists/bookworm/Release" -Toolchain "rust"
Assert-Eq "16 plain HTTP to an allowlisted host (deb.debian.org) is reachable through the proxy" "0" $r.ExitCode
Assert-Contains "17 a reached allowed plain-HTTP host returns a real response" $r.Output "HTTP 2"

$r = Start-IsolationContainer -Root $scr -Image "curlimages/curl:latest" -Command "curl -sS -m 10 -o /dev/null -w 'HTTP %{http_code}' http://neverssl.com/" -Toolchain "rust"
Assert-Contains "18 plain HTTP to a non-allowlisted host gets Squid's own denial, not a silent allow" $r.Output "HTTP 403"

# End-to-end proof this whole mechanism actually supports the feature's
# real purpose: installing and running Claude Code itself inside the
# sandbox (section 7's credential exception, section 9's always-present
# allowlist entries). Confirmed manually (2026-10-23) before writing any
# of this; this scenario locks that proof in as a regression check. The
# slowest scenario in this suite by a wide margin -- deliberately kept to
# one, not several, to bound that cost.
$installCmd = 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl ca-certificates >/dev/null 2>&1 && curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 && export PATH="$HOME/.local/bin:$PATH" && claude --version'
$r = Start-IsolationContainer -Root $scr -Image "debian:12-slim" -Command $installCmd -Toolchain "rust"
Assert-Eq "19 Claude Code installs and runs successfully inside the sandbox, end to end" "0" $r.ExitCode
Assert-Contains "20 the installed claude actually reports a version, not a stale/empty success" $r.Output "Claude Code"

Write-Host ""
Write-Host "=== Results: $($script:PassCount) passed, $($script:FailCount) failed ==="
if ($script:FailCount -gt 0) {
    Write-Host "Failed scenarios:"
    foreach ($n in $script:FailedNames) { Write-Host "  - $n" }
    exit 1
}
exit 0
