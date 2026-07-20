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

# Find real Python (skip Windows Store stub)
$PythonExe = $null
foreach ($candidate in @(
    (Join-Path $env:LOCALAPPDATA "miniconda3\python.exe"),
    (Join-Path $env:USERPROFILE "miniconda3\python.exe"),
    (Join-Path $env:USERPROFILE "anaconda3\python.exe"),
    "C:\Python313\python.exe", "C:\Python312\python.exe", "C:\Python311\python.exe",
    "C:\Program Files\Python3*\python.exe"
)) {
    $found = Get-Item $candidate -ErrorAction SilentlyContinue
    if ($found) { $PythonExe = $found.FullName; break }
}
if (-not $PythonExe) {
    # Try python3 command, exclude WindowsApps stubs
    $realPy = & { where.exe python3 2>$null } | Where-Object { $_ -notlike "*WindowsApps*" } | Select-Object -First 1
    if ($realPy) { $PythonExe = $realPy }
}
if (-not $PythonExe) { throw "Python 3 not found. Install miniconda or Python 3.x." }
Write-Host "Python: $PythonExe" -ForegroundColor DarkGray

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
    $conffiles = "/etc/config/skadik-gate`n"
    [System.IO.File]::WriteAllText((Join-Path $ControlDir "conffiles"), $conffiles, [System.Text.UTF8Encoding]::new($false))
    
    # postinst — must be LF only (CRLF breaks #!/bin/sh)
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
'@ -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText((Join-Path $ControlDir "postinst"), $postinst, [System.Text.UTF8Encoding]::new($false))
    
    # prerm — LF only
    $prerm = @'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    /etc/init.d/skadik-gate stop 2>/dev/null
    /etc/init.d/skadik-gate disable 2>/dev/null
}
'@ -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText((Join-Path $ControlDir "prerm"), $prerm, [System.Text.UTF8Encoding]::new($false))
    
    # debian-binary
    [System.IO.File]::WriteAllText((Join-Path $PkgDir "debian-binary"), "2.0`n", [System.Text.UTF8Encoding]::new($false))
    
    # Create control.tar.gz and data.tar.gz via Python (handles LF + Unix permissions)
    $buildPy = Join-Path $PkgDir "build_pkg.py"
    $pyScript = @"
import tarfile, io, os, sys, gzip, time

pkg_dir = sys.argv[1]
out_ipk = sys.argv[2]
control_dir = os.path.join(pkg_dir, 'control')
data_dir = os.path.join(pkg_dir, 'data')

def add_file(t, arcname, filepath, mode):
    with open(filepath, 'rb') as f:
        data = f.read()
    info = tarfile.TarInfo(name=arcname)
    info.size = len(data)
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = 'root'
    info.gname = 'root'
    t.addfile(info, io.BytesIO(data))

def add_bytes(t, arcname, data, mode):
    info = tarfile.TarInfo(name=arcname)
    info.size = len(data)
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = 'root'
    info.gname = 'root'
    t.addfile(info, io.BytesIO(data))

# Build inner tarballs in memory
ctrl_buf = io.BytesIO()
with tarfile.open(fileobj=ctrl_buf, mode='w:gz') as t:
    for name in sorted(os.listdir(control_dir)):
        fp = os.path.join(control_dir, name)
        mode = 0o755 if name in ('postinst', 'prerm') else 0o644
        add_file(t, name, fp, mode)
ctrl_data = ctrl_buf.getvalue()

data_buf = io.BytesIO()
with tarfile.open(fileobj=data_buf, mode='w:gz') as t:
    for root, dirs, files in os.walk(data_dir):
        for name in sorted(files):
            fp = os.path.join(root, name)
            arcname = os.path.relpath(fp, data_dir).replace(os.sep, '/')
            mode = 0o755 if (name.endswith('.sh') or 'init.d' in arcname) else 0o644
            add_file(t, arcname, fp, mode)
data_data = data_buf.getvalue()

deb_bin = b'2.0\n'

# Build outer .ipk as ar archive then gzip (opkg format)
def ar_entry(name, data, mode=0o644):
    now = int(time.time())
    header = bytearray(60)
    header[0:16] = name.encode('ascii').ljust(16)
    header[16:28] = str(now).encode('ascii').ljust(12)
    header[28:34] = b'0'.ljust(6)
    header[34:40] = b'0'.ljust(6)
    header[40:48] = ('%o' % mode).encode('ascii').ljust(8)
    header[48:58] = str(len(data)).encode('ascii').rjust(10)
    header[58:60] = b'\x60\x0a'
    result = bytes(header) + data
    if len(data) % 2:
        result += b'\n'
    return result

raw = b'!<arch>\n'
raw += ar_entry('debian-binary', deb_bin)
raw += ar_entry('control.tar.gz', ctrl_data)
raw += ar_entry('data.tar.gz', data_data)

with gzip.open(out_ipk, 'wb') as f:
    f.write(raw)

print('OK: control.tar.gz=%d data.tar.gz=%d ipk=%d' % (len(ctrl_data), len(data_data), os.path.getsize(out_ipk)))
"@
    [System.IO.File]::WriteAllText($buildPy, $pyScript, (New-Object System.Text.UTF8Encoding $false))
    $IpkName = "${PkgName}_${Version}_${Arch}.ipk"
    $IpkPath = Join-Path $BuildDir $IpkName
    & $PythonExe $buildPy $PkgDir $IpkPath
    
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
            "usr\lib\lua\luci\view\skadik-gate",
            "usr\lib\lua\luci\i18n"
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

        # Compile i18n translations
        $po2lmo = Join-Path $ScriptDir "build\po2lmo.py"
        $i18nSrc = Join-Path $ScriptDir "luci-app-skadik-gate\luasrc\i18n"
        $i18nDst = Join-Path $DataDir "usr\lib\lua\luci\i18n"
        foreach ($po in Get-ChildItem "$i18nSrc\*.po") {
            $lmoName = $po.BaseName + ".lmo"
            & $PythonExe $po2lmo $po.FullName (Join-Path $i18nDst $lmoName)
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
