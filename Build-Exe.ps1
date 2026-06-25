<#
.SYNOPSIS
    Bygger FormatDiskTool.exe fra .ps1 og signerer den med et self-signed
    code-signing-sertifikat.

.DESCRIPTION
    Steg:
      1. Installerer ps2exe ved behov.
      2. Kompilerer FormatDiskTool.ps1 -> FormatDiskTool.exe (krever admin, skjult konsoll).
      3. Lager (eller gjenbruker) et self-signed code-signing-sertifikat.
      4. Signerer exe-en med tidsstempel.
      5. (Valgfritt) Importerer sertifikatet i Trusted Root + Trusted Publisher
         slik at Windows stoler på exe-en på DENNE maskinen.

    Self-signed signatur fjerner SmartScreen-advarselen kun på maskiner der
    sertifikatet er importert som klarert. For nedlasting uten advarsel for
    alle trengs et OV-/EV-sertifikat fra en kommersiell CA (koster penger).

.PARAMETER TrustOnThisMachine
    Importer sertifikatet i Trusted Root/Publisher (krever admin).
#>
param(
    [string]$Source  = 'C:\Users\roymo\Format\FormatDiskTool.ps1',
    [string]$Output  = 'C:\Users\roymo\Format\FormatDiskTool.exe',
    [string]$Subject = 'CN=Roy Morken',
    [switch]$TrustOnThisMachine
)

$ErrorActionPreference = 'Stop'

# 1. ps2exe
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host '[1/4] Installerer ps2exe ...' -ForegroundColor Cyan
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

# 2. Kompiler
Write-Host '[2/4] Bygger exe ...' -ForegroundColor Cyan
Invoke-ps2exe -inputFile $Source -outputFile $Output `
    -requireAdmin -noConsole -title 'Format Disk Tool' -product 'Format Disk Tool'

# 3. Sertifikat (gjenbruk hvis det finnes)
Write-Host '[3/4] Henter/lager code-signing-sertifikat ...' -ForegroundColor Cyan
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -eq $Subject } |
    Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
        -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(3)
    Write-Host "      Nytt sertifikat laget: $($cert.Thumbprint)" -ForegroundColor Green
}
else {
    Write-Host "      Gjenbruker sertifikat: $($cert.Thumbprint)" -ForegroundColor Green
}

# 4. Signer
Write-Host '[4/4] Signerer exe ...' -ForegroundColor Cyan
$sig = Set-AuthenticodeSignature -FilePath $Output -Certificate $cert `
    -TimeStampServer 'http://timestamp.digicert.com'
Write-Host "      Signaturstatus: $($sig.Status)" -ForegroundColor Green

# Valgfritt: gjor sertifikatet klarert pa denne maskinen (krever admin)
if ($TrustOnThisMachine) {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'ADVARSEL: -TrustOnThisMachine krever admin. Hopper over import.' -ForegroundColor Yellow
    }
    else {
        $tmp = Join-Path $env:TEMP 'fdt-codesign.cer'
        Export-Certificate -Cert $cert -FilePath $tmp | Out-Null
        Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
        Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
        Remove-Item $tmp -Force
        Write-Host '      Sertifikat importert i Trusted Root + Trusted Publisher.' -ForegroundColor Green
    }
}

Write-Host "`nFerdig. Signert exe: $Output" -ForegroundColor Green
