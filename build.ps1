# Skadik-Gate: Build .ipk packages on Windows
# Creates installable OpenWRT packages without SDK
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
    
    New-Item -ItemType Directory -Force -Path $DataDir, $ControlDir | Out-Null
    
    # Run copy script
    & $CopyFiles $DataDir
    
    # Create control file
    $controlContent = @"
Package: $PkgName
Version: $Version
Depends: $Depends
Architecture: $Arch
Maintainer: Skadik <noreply@skadik.dev>
Section: $Section
Source: https://github.com/RaconFloup/Skadik-Gate
Description: $Description
"@
    Set-Content -Path (Join-Path $ControlDir "control") -Value $controlContent -Encoding UTF8
    
    # Create conffiles
    $conffiles = @"
/etc/config/skadik-gate
/etc/skadik-gate/
"@
    Set-Content -Path (Join-Path $ControlDir "conffiles") -Value $conffiles -Encoding UTF8
    
    # Create postinst
    $postinst = @"
#!/bin/sh
[ -n "`${IPKG_INSTROOT}" ] || {
    chmod +x /usr/bin/skadik-gate 2>/dev/null
    chmod +x /usr/bin/skadik-gate-sub 2>/dev/null
    chmod +x /usr/share/skadik-gate/*.sh 2>/dev/null
    chmod +x /etc/init.d/skadik-gate 2>/dev/null
    mkdir -p /etc/skadik-gate/nodes
    mkdir -p /var/log/skadik-gate
    /etc/init.d/skadik-gate enable 2>/dev/null
}
"@
    Set-Content -Path (Join-Path $ControlDir "postinst") -Value $postinst -Encoding UTF8
    
    # Create prerm
    $prerm = @"
#!/bin/sh
[ -n "`${IPKG_INSTROOT}" ] || {
    /etc/init.d/skadik-gate stop 2>/dev/null
    /etc/init.d/skadik-gate disable 2>/dev/null
}
"@
    Set-Content -Path (Join-Path $ControlDir "prerm") -Value $prerm -Encoding UTF8
    
    # Create debian-binary
    Set-Content -Path (Join-Path $PkgDir "debian-binary") -Value "2.0" -Encoding UTF8
    
    # Create data.tar.gz
    Push-Location $DataDir
    tar -czf (Join-Path $PkgDir "data.tar.gz") *
    Pop-Location
    
    # Create control.tar.gz
    Push-Location $ControlDir
    tar -czf (Join-Path $PkgDir "control.tar.gz") *
    Pop-Location
    
    # Create .ipk package (tar archive with specific order)
    $IpkName = "${PkgName}_${Version}_${Arch}.ipk"
    $IpkPath = Join-Path $BuildDir $IpkName
    
    Push-Location $PkgDir
    tar -cf $IpkPath debian-binary control.tar.gz data.tar.gz
    Pop-Location
    
    Write-Host "OK: $IpkPath" -ForegroundColor Green
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
Write-Host "Packages created:" -ForegroundColor Cyan
Get-ChildItem "$BuildDir\*.ipk" | ForEach-Object {
    Write-Host "  $($_.FullName)" -ForegroundColor White
}
Write-Host ""
Write-Host "Install on OpenWRT router:" -ForegroundColor Yellow
Write-Host "  1. Copy packages to router:"
Write-Host "     scp $BuildDir\*.ipk root@router-ip:/tmp/" -ForegroundColor White
Write-Host ""
Write-Host "  2. Install packages:"
Write-Host "     ssh root@router-ip 'opkg install /tmp/skadik-gate_*.ipk /tmp/luci-app-skadik-gate_*.ipk'" -ForegroundColor White
Write-Host ""
Write-Host "  3. Or use the quick install script:"
Write-Host "     wget -O- https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/install.sh | sh" -ForegroundColor White
Write-Host ""
