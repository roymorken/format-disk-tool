<#
.SYNOPSIS
    Lager en ≤4 GB FAT16-partisjon på en USB/disk som er for stor til FAT16.

.DESCRIPTION
    FAT16 støtter maks 4 GB. En 8 GB+ disk kan derfor ikke formateres FAT16 i sin
    helhet. Dette scriptet sletter disken, lager EN partisjon på valgt størrelse
    (standard 3,9 GB) og formaterer den FAT16. Resten av disken blir ubrukt.

    ADVARSEL: Sletter ALT på den valgte disken permanent.
#>
param(
    [int]$SizeMB = 3900,          # Partisjonsstørrelse i MB (maks ~4000 for FAT16)
    [string]$Label = 'USB'
)

# Krev administrator
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

if ($SizeMB -gt 4000) {
    Write-Host "FAT16 maks ~4 GB. Setter størrelse til 4000 MB." -ForegroundColor Yellow
    $SizeMB = 4000
}

# List kandidat-disker (ekskluder system-/boot-disk)
Write-Host "`n=== Tilgjengelige disker (system-disk skjult) ===" -ForegroundColor Cyan
$disks = Get-Disk | Where-Object { -not $_.IsBoot -and -not $_.IsSystem }
if (-not $disks) { Write-Host "Ingen ikke-system-disker funnet."; pause; exit }

$disks | Format-Table Number, FriendlyName, @{N='GB';E={[math]::Round($_.Size/1GB,1)}}, BusType -AutoSize

$num = Read-Host "`nSkriv DISK-NUMMER på USB-en du vil formatere FAT16"
$disk = $disks | Where-Object { $_.Number -eq [int]$num }
if (-not $disk) { Write-Host "Ugyldig disk-nummer." -ForegroundColor Red; pause; exit }

$gb = [math]::Round($disk.Size/1GB,1)
Write-Host "`nVALGT: Disk $($disk.Number) - $($disk.FriendlyName) - $gb GB" -ForegroundColor Yellow
Write-Host "Dette SLETTER ALT på disken og lager en $([math]::Round($SizeMB/1024,1)) GB FAT16-partisjon." -ForegroundColor Red

$confirm = Read-Host "Skriv disk-nummeret '$num' en gang til for å bekrefte"
if ($confirm.Trim() -ne $num.Trim()) { Write-Host "Avbrutt." -ForegroundColor Yellow; pause; exit }

try {
    Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
    $part = New-Partition -DiskNumber $disk.Number -Size ($SizeMB * 1MB) -AssignDriveLetter -ErrorAction Stop
    Format-Volume -DriveLetter $part.DriveLetter -FileSystem FAT -NewFileSystemLabel $Label -Confirm:$false -Force -ErrorAction Stop | Out-Null
    Write-Host "`nFerdig: $($part.DriveLetter): formatert FAT16 ($($Label))." -ForegroundColor Green
}
catch {
    Write-Host "`nFeil: $($_.Exception.Message)" -ForegroundColor Red
}
pause
