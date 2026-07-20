# Skadik-Gate: Build .ipk packages on Windows
# Creates proper ar-format .ipk packages compatible with opkg
#
# Usage: .\build.ps1
# Or:    pwsh build.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $ScriptDir "build\ipk"
$Version = "1.0.0"
$Arch = "all"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Skadik-Gate Package Builder" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Clean and create build dir
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

function New-ArArchive {
    param(
        [string]$OutputPath,
        [string[]]$Files
    )
    
    $stream = [System.IO.File]::Create($OutputPath)
    $writer = [System.IO.BinaryWriter]::new($stream)
    
    # ar magic
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes("!<arch>`n"))
    
    foreach ($file in $Files) {
        $item = Get-Item $file
        $name = $item.Name
        $size = $item.Length
        $data = [System.IO.File]::ReadAllBytes($file)
        
        # Header: name(16) + timestamp(12) + owner(6) + group(6) + mode(8) + size(10) + magic(2)
        $header = New-Object byte[] 60
        
        # Name (16 bytes, padded with spaces, trailing /)
        $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($name + "/")
        [Array]::Copy($nameBytes, 0, $header, 0, [Math]::Min($nameBytes.Length, 16))
        
        # Timestamp (12 bytes)
        $ts = [System.Text.Encoding]::ASCII.GetBytes("0           ")
        [Array]::Copy($ts, 0, $header, 16, 12)
        
        # Owner (6 bytes)
        $ow = [System.Text.Encoding]::ASCII.GetBytes("0     ")
        [Array]::Copy($ow, 0, $header, 28, 6)
        
        # Group (6 bytes)
        [Array]::Copy($ow, 0, $header, 34, 6)
        
        # Mode (8 bytes)
        $mode = [System.Text.Encoding]::ASCII.GetBytes("100644   ")
        [Array]::Copy($mode, 0, $header, 40, 8)
        
        # Size (10 bytes, right-aligned)
        $sizeStr = $size.ToString().PadLeft(10)
        $sizeBytes = [System.Text.Encoding]::ASCII.GetBytes($sizeStr)
        [Array]::Copy($sizeBytes, 0, $header, 48, 10)
        
        # Magic (2 bytes)
        $header[58] = [byte]0x60  # `
        $header[59] = [byte]0x0A  # \n
        
        $writer.Write($header)
        $writer.Write($data)
        
        # Pad to 2-byte boundary
        if ($size % 2 -ne 0) {
            $writer.Write([byte]0x0A)
        }
    }
    
    $writer.Close()
    $stream.Close()
}

function New-GzipFile {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )
    
    $inStream = [System.IO.File]::OpenRead($InputPath)
    $outStream = [System.IO.File]::Create($OutputPath)
    $gzStream = [System.IO.Compression.GZipStream]::new($outStream, [System.IO.Compression.CompressionLevel]::Optimal)
    $inStream.CopyTo($gzStream)
    $gzStream.Close()
    $inStream.Close()
    $outStream.Close()
}

function Build-IPK {
    param(
        [string]$PkgName,
        [string]$Description,
        [string]$Depends,
        [string]$Section,
        [scriptblock]$CopyFiles
    )
    
    Write-Host "`nBuilding $PkgName..." -ForegroundColor Yellow
    
    $PkgDir = Join-Path $BuildDir $PkgName
    $DataDir = Join-Path $PkgDir "data"
    $ControlDir = Join-Path $PkgDir "control"
    
    if (Test-Path $PkgDir) { Remove-Item -Recurse -Force $PkgDir }
    New-Item -ItemType Directory -Force -Path $DataDir, $ControlDir | Out-Null
    
    # Run copy script
    & $CopyFiles $DataDir
    
    # Create control file (Unix line endings)
    $controlLines = @(
        "Package: $PkgName"
        "Version: $Version"
        "Depends: $Depends"
        "Architecture: $Arch"
        "Maintainer: Skadik <noreply@skadik.dev>"
        "Section: $Section"
        "Source: https://github.com/RaconFloup/Skadik-Gate"
        "Description: $Description"
        ""
    )
    $controlContent = $controlLines -join "`n"
    [System.IO.File]::WriteAllText((Join-Path $ControlDir "control"), $controlContent, [System.Text.UTF8Encoding]::new($false))
    
    # conffiles
    $conffiles = "/etc/config/skadik-gate`n/etc/skadik-gate/`n"
    [System.IO.File]::WriteAllText((Join-Path $ControlDir "conffiles"), $conffiles, [System.Text.UTF8Encoding]::new($false))
    
    # postinst
    $postinst = @'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    chmod +x /usr/bin/skadik-gate 2>/dev/null
    chmod +x /usr/bin/skadik-gate-sub 2>/dev/null
    chmod +x /usr/share/skadik-gate/*.sh 2>/dev/null
    chmod +x /etc/init.d/skadik-gate 2>/dev/null
    mkdir -p /etc/skadik-gate/nodes
    mkdir -p /var/log/skadik-gate
    /etc/init.d/skadik-gate enable 2>/dev/null
}
'@
    [System.IO.File]::WriteAllText((Join-Path $ControlDir "postinst"), $postinst, [System.Text.UTF8Encoding]::new($false))
    
    # prerm
    $prerm = @'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    /etc/init.d/skadik-gate stop 2>/dev/null
    /etc/init.d/skadik-gate disable 2>/dev/null
}
'@
    [System.IO.File]::WriteAllText((Join-Path $ControlDir "prerm"), $prerm, [System.Text.UTF8Encoding]::new($false))
    
    # debian-binary
    [System.IO.File]::WriteAllText((Join-Path $PkgDir "debian-binary"), "2.0`n", [System.Text.UTF8Encoding]::new($false))
    
    # Create data.tar.gz with tar
    Push-Location $DataDir
    $dataFiles = Get-ChildItem -Recurse -File | ForEach-Object { $_.FullName.Substring($DataDir.Length + 1) }
    tar -czf (Join-Path $PkgDir "data.tar.gz") @dataFiles
    Pop-Location
    
    # Create control.tar.gz with tar
    Push-Location $ControlDir
    $controlFiles = Get-ChildItem -File | ForEach-Object { $_.Name }
    tar -czf (Join-Path $PkgDir "control.tar.gz") @controlFiles
    Pop-Location
    
    # Create .ipk as ar archive
    $IpkName = "${PkgName}_${Version}_${Arch}.ipk"
    $IpkPath = Join-Path $BuildDir $IpkName
    
    $arFiles = @(
        (Join-Path $PkgDir "debian-binary"),
        (Join-Path $PkgDir "control.tar.gz"),
        (Join-Path $PkgDir "data.tar.gz")
    )
    
    New-ArArchive -OutputPath $IpkPath -Files $arFiles
    
    $size = (Get-Item $IpkPath).Length
    Write-Host "OK: $IpkName ($size bytes)" -ForegroundColor Green
    return $IpkPath
}

# ============================================
# Build skadik-gate core package
# ============================================
$coreFiles = Build-IPK -PkgName "skadik-gate" `
    -Description "Skadik-Gate VPN Client for Remnawave panel" `
    -Depends "xray-core, curl, kmod-nft-tproxy, nftables, ip-full" `
    -Section "net" `
    -CopyFiles {
        param($DataDir)
        
        $dirs = @(
            "etc\config",
            "etc\init.d",
            "etc\cron.d",
            "etc\uci-defaults",
            "usr\bin",
            "usr\share\skadik-gate"
        )
        foreach ($d in $dirs) {
            New-Item -ItemType Directory -Force -Path (Join-Path $DataDir $d) | Out-Null
        }
        
        $files = @(
            @{ Src = "files\etc\config\skadik-gate"; Dst = "etc\config\skadik-gate" }
            @{ Src = "files\etc\init.d\skadik-gate"; Dst = "etc\init.d\skadik-gate" }
            @{ Src = "files\etc\cron.d\skadik-gate"; Dst = "etc\cron.d\skadik-gate" }
            @{ Src = "files\etc\uci-defaults\skadik-gate"; Dst = "etc\uci-defaults\skadik-gate" }
            @{ Src = "files\usr\bin\skadik-gate"; Dst = "usr\bin\skadik-gate" }
            @{ Src = "files\usr\bin\skadik-gate-sub"; Dst = "usr\bin\skadik-gate-sub" }
        )
        foreach ($f in $files) {
            Copy-Item (Join-Path $ScriptDir $f.Src) (Join-Path $DataDir $f.Dst)
        }
        
        $scripts = Get-ChildItem (Join-Path $ScriptDir "files\usr\share\skadik-gate\*.sh")
        foreach ($s in $scripts) {
            Copy-Item $s.FullName (Join-Path $DataDir "usr\share\skadik-gate\$($s.Name)")
        }
    }

# ============================================
# Build luci-app-skadik-gate
# ============================================
$luciFiles = Build-IPK -PkgName "luci-app-skadik-gate" `
    -Description "LuCI web interface for Skadik-Gate VPN client" `
    -Depends "skadik-gate, luci-base, luci-compat" `
    -Section "luci" `
    -CopyFiles {
        param($DataDir)
        
        $dirs = @(
            "usr\lib\lua\luci\controller",
            "usr\lib\lua\luci\model\cbi\skadik-gate",
            "usr\lib\lua\luci\view\skadik-gate"
        )
        foreach ($d in $dirs) {
            New-Item -ItemType Directory -Force -Path (Join-Path $DataDir $d) | Out-Null
        }
        
        Copy-Item (Join-Path $ScriptDir "luci-app-skadik-gate\luasrc\controller\skadik-gate.lua") `
            (Join-Path $DataDir "usr\lib\lua\luci\controller\")
        
        $models = Get-ChildItem (Join-Path $ScriptDir "luci-app-skadik-gate\luasrc\model\cbi\skadik-gate\*.lua")
        foreach ($m in $models) {
            Copy-Item $m.FullName (Join-Path $DataDir "usr\lib\lua\luci\model\cbi\skadik-gate\$($m.Name)")
        }
        
        $views = Get-ChildItem (Join-Path $ScriptDir "luci-app-skadik-gate\luasrc\view\skadik-gate\*.htm")
        foreach ($v in $views) {
            Copy-Item $v.FullName (Join-Path $DataDir "usr\lib\lua\luci\view\skadik-gate\$($v.Name)")
        }
    }

# ============================================
# Summary
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  BUILD COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Packages:" -ForegroundColor Cyan
Get-ChildItem "$BuildDir\*.ipk" | ForEach-Object {
    Write-Host "  $($_.Name) ($($_.Length) bytes)" -ForegroundColor White
}
Write-Host ""
Write-Host "Install on router:" -ForegroundColor Yellow
Write-Host "  wget -O /tmp/sg.ipk https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/build/ipk/skadik-gate_1.0.0_all.ipk" -ForegroundColor White
Write-Host "  wget -O /tmp/sg-luci.ipk https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/build/ipk/luci-app-skadik-gate_1.0.0_all.ipk" -ForegroundColor White
Write-Host "  opkg install /tmp/sg.ipk /tmp/sg-luci.ipk" -ForegroundColor White
Write-Host ""
