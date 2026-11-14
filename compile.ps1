# Compile MCBEPlay with Aut2Exe. UPX is not used (/nopack).
# Requires AutoIt 3.3.14 or newer: https://www.autoitscript.com/site/autoit/downloads/
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$candidates = @(
    "${env:ProgramFiles(x86)}\AutoIt3\Aut2Exe\Aut2exe.exe",
    "$env:ProgramFiles\AutoIt3\Aut2Exe\Aut2exe.exe"
)
$aut2exe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $aut2exe) {
    Write-Error "Aut2Exe not found. Install AutoIt, then run this script again."
}

$icon = Join-Path $PSScriptRoot 'icon.ico'

function Invoke-Aut2Exe {
    param(
        [Parameter(Mandatory = $true)][string]$InFile,
        [Parameter(Mandatory = $true)][string]$OutFile
    )
    $argList = @('/in', $InFile, '/out', $OutFile, '/nopack')
    if (Test-Path -LiteralPath $icon) {
        $argList += @('/icon', $icon)
    }
    Write-Host "Compiling $InFile -> $OutFile"
    Write-Host "Aut2Exe: $aut2exe"
    # Calling Aut2Exe with & often leaves $LASTEXITCODE empty. Wait on the process.
    $p = Start-Process -FilePath $aut2exe -ArgumentList $argList -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "Aut2Exe failed for $InFile (exit $($p.ExitCode))"
    }
    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Aut2Exe reported success but $OutFile was not created"
    }
    $item = Get-Item -LiteralPath $OutFile
    Write-Host ("Built {0} ({1} bytes)" -f $item.FullName, $item.Length)
}

Invoke-Aut2Exe -InFile 'mcbeplay.au3' -OutFile 'mcbeplay.exe'
Invoke-Aut2Exe -InFile 'bds.au3' -OutFile 'bds.exe'
Write-Host "Done. mcbeplay.exe and bds.exe were built without UPX."
Write-Host "Copy those two files next to the existing options.txt. Do not overwrite options.txt, logs, or saves."
