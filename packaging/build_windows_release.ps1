param(
    [string]$GodotExecutable = "",
    [string]$PythonExecutable = "python",
    [switch]$EmbedApiCredential
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$BuildRoot = Join-Path $ProjectRoot ("build\release_work\" + [DateTime]::Now.ToString("yyyyMMdd_HHmmss"))
$StageRoot = Join-Path $BuildRoot "BlindspotRelay-Windows"
$RuntimeRoot = Join-Path $StageRoot "_runtime"
$ReleaseRoot = Join-Path $ProjectRoot "build\releases"
$ZipPath = Join-Path $ReleaseRoot "BlindspotRelay-Windows-v0.4.0.zip"

function Assert-ProjectChild([string]$PathToCheck) {
    $projectPrefix = $ProjectRoot.TrimEnd('\') + '\'
    $fullPath = [System.IO.Path]::GetFullPath($PathToCheck)
    if (-not $fullPath.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the project: $fullPath"
    }
}

foreach ($target in @($BuildRoot, $ReleaseRoot, $ZipPath)) {
    Assert-ProjectChild $target
}

if (-not $GodotExecutable) {
    if ($env:GODOT_EXE) {
        $GodotExecutable = $env:GODOT_EXE
    } else {
        $desktopCandidate = "C:\Users\ethanypan\Desktop\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
        if (Test-Path -LiteralPath $desktopCandidate) {
            $GodotExecutable = $desktopCandidate
        } else {
            $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
            if ($godotCommand) {
                $GodotExecutable = $godotCommand.Source
            }
        }
    }
}
if (-not $GodotExecutable -or -not (Test-Path -LiteralPath $GodotExecutable)) {
    throw "Godot 4.6 executable not found. Pass -GodotExecutable or set GODOT_EXE."
}

$resolvedGodot = (Resolve-Path -LiteralPath $GodotExecutable).Path
if ([System.IO.Path]::GetFileNameWithoutExtension($resolvedGodot).EndsWith("_console")) {
    $GodotConsole = $resolvedGodot
    $GodotGui = $resolvedGodot.Substring(0, $resolvedGodot.Length - "_console.exe".Length) + ".exe"
} else {
    $GodotGui = $resolvedGodot
    $GodotConsole = Join-Path ([System.IO.Path]::GetDirectoryName($resolvedGodot)) (([System.IO.Path]::GetFileNameWithoutExtension($resolvedGodot)) + "_console.exe")
    if (-not (Test-Path -LiteralPath $GodotConsole)) {
        $GodotConsole = $GodotGui
    }
}
if (-not (Test-Path -LiteralPath $GodotGui)) {
    throw "Godot GUI runtime not found beside the console executable: $GodotGui"
}

& $PythonExecutable -m PyInstaller --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller is not installed for $PythonExecutable."
}

New-Item -ItemType Directory -Force -Path $RuntimeRoot, $ReleaseRoot | Out-Null

Write-Host "[1/4] Compiling Godot resource pack..."
$gameExe = Join-Path $RuntimeRoot "BlindspotGame.exe"
$gamePack = Join-Path $RuntimeRoot "BlindspotGame.pck"
& $GodotConsole --headless --path $ProjectRoot --export-pack "Windows Desktop" $gamePack
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $gamePack)) {
    throw "Godot resource-pack export failed."
}
Copy-Item -LiteralPath $GodotGui -Destination $gameExe

Write-Host "[2/4] Freezing local AI relay..."
$relayArgs = @(
    "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile",
    "--name", "BlindspotRelayServer",
    "--distpath", $RuntimeRoot,
    "--workpath", (Join-Path $BuildRoot "pyinstaller\relay\work"),
    "--specpath", (Join-Path $BuildRoot "pyinstaller\relay\spec")
)
if ($EmbedApiCredential) {
    $envFile = Join-Path $ProjectRoot ".env"
    if (-not (Test-Path -LiteralPath $envFile)) {
        throw "-EmbedApiCredential was requested but project .env is missing."
    }
    $relayArgs += @("--add-data", "$envFile;.")
}
$relayArgs += (Join-Path $ProjectRoot "server.py")
& $PythonExecutable @relayArgs
if ($LASTEXITCODE -ne 0) {
    throw "AI relay packaging failed."
}

Write-Host "[3/4] Building one-click launcher..."
$launcherArgs = @(
    "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile",
    "--name", "BlindspotRelay",
    "--distpath", $StageRoot,
    "--workpath", (Join-Path $BuildRoot "pyinstaller\launcher\work"),
    "--specpath", (Join-Path $BuildRoot "pyinstaller\launcher\spec"),
    (Join-Path $PSScriptRoot "launcher.py")
)
& $PythonExecutable @launcherArgs
if ($LASTEXITCODE -ne 0) {
    throw "Launcher packaging failed."
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot "PLAYER_README_zh-CN.txt") -Destination (Join-Path $StageRoot "README_zh-CN.txt")
Copy-Item -LiteralPath (Join-Path $ProjectRoot "docs\AI_AND_PRIVACY.md") -Destination (Join-Path $StageRoot "AI_AND_PRIVACY.md")

$hashLines = Get-ChildItem -File -Recurse -LiteralPath $StageRoot |
    Where-Object Name -ne "SHA256SUMS.txt" |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($StageRoot.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        "$hash *$relative"
    }
[System.IO.File]::WriteAllLines((Join-Path $StageRoot "SHA256SUMS.txt"), $hashLines, [System.Text.UTF8Encoding]::new($false))

Write-Host "[4/4] Creating ZIP..."
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -Force -LiteralPath $ZipPath
}
Compress-Archive -Path (Join-Path $StageRoot "*") -DestinationPath $ZipPath -CompressionLevel Optimal

$zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToLowerInvariant()
Write-Host "Release: $ZipPath"
Write-Host "SHA256: $zipHash"
