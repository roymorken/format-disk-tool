<#
.SYNOPSIS
    Format Disk Tool - GUI for å formatere disker/USB i FAT16, FAT32 eller NTFS.

.DESCRIPTION
    Windows Forms-grensesnitt som lister alle ikke-system-volumer og lar deg
    formatere en valgt disk. Bygd med flere sikkerhetsvakter:
      - OS-/system-volumet ekskluderes alltid fra lista (kan ikke velges).
      - Krever administrator-rettigheter (auto-eskalerer ved oppstart).
      - Dobbel bekreftelse + krav om å taste inn drevbokstaven før formatering.
      - FAT16 blokkeres for volumer over 4 GB (filsystem-grense).

    ADVARSEL: Formatering sletter ALT innhold på det valgte volumet permanent.
#>

# --- Krev administrator: auto-eskaler hvis vi ikke kjører som admin ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Konstanter ---
$FsMap = @{
    'FAT16' = 'FAT'      # Windows kaller FAT16 for "FAT"
    'FAT32' = 'FAT32'
    'NTFS'  = 'NTFS'
}
$Fat16MaxBytes = 4GB     # FAT16 støtter ikke volumer over 4 GB
$Fat16PartitionMB = 3900 # Størrelse (MB) på FAT16-partisjon når en stor disk repartisjoneres

# --- Hent formaterbare volumer (alt unntatt system-/OS-drevet) ---
function Get-FormattableVolumes {
    $sysDrive = ($env:SystemDrive).TrimEnd(':')   # f.eks. "C"
    Get-Volume |
        Where-Object {
            $_.DriveLetter -and
            $_.DriveLetter -ne $sysDrive -and
            $_.DriveType -in @('Removable', 'Fixed')
        } |
        Sort-Object DriveLetter
}

function Format-VolumeRow {
    param($vol)
    $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { '(uten navn)' }
    $sizeGb = [math]::Round($vol.Size / 1GB, 1)
    $fs = if ($vol.FileSystem) { $vol.FileSystem } else { 'RAW' }
    return ('{0}:  {1}  |  {2} GB  |  {3}  |  {4}' -f `
        $vol.DriveLetter, $label, $sizeGb, $fs, $vol.DriveType)
}

# --- Bygg GUI ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Format Disk Tool'
$form.Size = New-Object System.Drawing.Size(520, 395)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Font = $font

# Disk-velger
$lblDisk = New-Object System.Windows.Forms.Label
$lblDisk.Text = 'Disk:'
$lblDisk.Location = New-Object System.Drawing.Point(20, 25)
$lblDisk.Size = New-Object System.Drawing.Size(70, 22)
$form.Controls.Add($lblDisk)

$cmbDisk = New-Object System.Windows.Forms.ComboBox
$cmbDisk.Location = New-Object System.Drawing.Point(95, 22)
$cmbDisk.Size = New-Object System.Drawing.Size(315, 24)
$cmbDisk.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbDisk)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Oppdater'
$btnRefresh.Location = New-Object System.Drawing.Point(418, 21)
$btnRefresh.Size = New-Object System.Drawing.Size(64, 26)
$form.Controls.Add($btnRefresh)

# Format-velger
$lblFs = New-Object System.Windows.Forms.Label
$lblFs.Text = 'Format:'
$lblFs.Location = New-Object System.Drawing.Point(20, 65)
$lblFs.Size = New-Object System.Drawing.Size(70, 22)
$form.Controls.Add($lblFs)

$cmbFs = New-Object System.Windows.Forms.ComboBox
$cmbFs.Location = New-Object System.Drawing.Point(95, 62)
$cmbFs.Size = New-Object System.Drawing.Size(330, 24)
$cmbFs.DropDownStyle = 'DropDownList'
[void]$cmbFs.Items.AddRange(@('FAT16', 'FAT32', 'NTFS'))
$cmbFs.SelectedItem = 'FAT32'
$form.Controls.Add($cmbFs)

# Volumnavn / label
$lblLabel = New-Object System.Windows.Forms.Label
$lblLabel.Text = 'Volumnavn:'
$lblLabel.Location = New-Object System.Drawing.Point(20, 105)
$lblLabel.Size = New-Object System.Drawing.Size(70, 22)
$form.Controls.Add($lblLabel)

$txtLabel = New-Object System.Windows.Forms.TextBox
$txtLabel.Location = New-Object System.Drawing.Point(95, 102)
$txtLabel.Size = New-Object System.Drawing.Size(330, 24)
$txtLabel.MaxLength = 32
$form.Controls.Add($txtLabel)

# Hurtigformat
$chkQuick = New-Object System.Windows.Forms.CheckBox
$chkQuick.Text = 'Hurtigformat'
$chkQuick.Location = New-Object System.Drawing.Point(95, 135)
$chkQuick.Size = New-Object System.Drawing.Size(330, 24)
$chkQuick.Checked = $true
$form.Controls.Add($chkQuick)

# Formater-knapp
$btnFormat = New-Object System.Windows.Forms.Button
$btnFormat.Text = 'FORMATER'
$btnFormat.Location = New-Object System.Drawing.Point(150, 175)
$btnFormat.Size = New-Object System.Drawing.Size(200, 40)
$btnFormat.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 50)
$btnFormat.ForeColor = [System.Drawing.Color]::White
$btnFormat.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnFormat)

# Framdriftslinje (marquee - Format-Volume gir ingen prosent)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 222)
$progress.Size = New-Object System.Drawing.Size(465, 14)
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30
$progress.Visible = $false
$form.Controls.Add($progress)

# Statuslinje
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(20, 245)
$lblStatus.Size = New-Object System.Drawing.Size(465, 60)
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblStatus)

# Timer som poller bakgrunnsjobben mens GUI holdes responsivt
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400

# --- Logikk ---
$script:volumes = @()
$script:job = $null
$script:ctx = $null

function Update-DiskList {
    $cmbDisk.Items.Clear()
    $script:volumes = @(Get-FormattableVolumes)
    if ($script:volumes.Count -eq 0) {
        $lblStatus.Text = 'Ingen formaterbare volumer funnet. (System-drevet er alltid skjult.)'
        $btnFormat.Enabled = $false
        return
    }
    foreach ($v in $script:volumes) {
        [void]$cmbDisk.Items.Add((Format-VolumeRow $v))
    }
    $cmbDisk.SelectedIndex = 0
    $btnFormat.Enabled = $true
    $lblStatus.Text = ('{0} volum(er) funnet. System-drevet ({1}) er skjult og kan ikke velges.' -f `
        $script:volumes.Count, $env:SystemDrive)
}

$btnRefresh.Add_Click({ Update-DiskList })

$btnFormat.Add_Click({
    $idx = $cmbDisk.SelectedIndex
    if ($idx -lt 0) { return }
    $vol = $script:volumes[$idx]
    $fsKey = [string]$cmbFs.SelectedItem
    $fsValue = $FsMap[$fsKey]
    $label = $txtLabel.Text.Trim()
    $quick = $chkQuick.Checked

    # Sikkerhetsvakt: FAT16 maks 4 GB. Tilby repartisjonering i stedet for å bare blokkere.
    $doRepartition = $false
    if ($fsKey -eq 'FAT16' -and $vol.Size -gt $Fat16MaxBytes) {
        $partGb = [math]::Round($Fat16PartitionMB / 1024, 1)
        $volGb = [math]::Round($vol.Size / 1GB, 1)
        $msg = "FAT16 stotter ikke volumer over 4 GB ($($vol.DriveLetter): er $volGb GB).`n`n" +
               "Vil du lage EN $partGb GB FAT16-partisjon i stedet? Resten av disken blir ubrukt.`n`n" +
               "Dette SLETTER HELE disken (alle partisjoner)."
        $ans = [System.Windows.Forms.MessageBox]::Show(
            $msg, 'FAT16 - lag mindre partisjon?', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
        $doRepartition = $true
    }

    # Bekreftelse 1: ja/nei-advarsel
    $labelTxt = if ($label) { $label } else { '(tomt)' }
    $quickTxt = if ($quick) { 'Ja' } else { 'Nei (full)' }
    $msg1 = "ADVARSEL: Dette sletter ALT pa volum $($vol.DriveLetter): ($($vol.FileSystemLabel)) PERMANENT.`n`n" +
            "Filsystem: $fsKey`nVolumnavn: $labelTxt`nHurtigformat: $quickTxt`n`nVil du fortsette?"
    $confirm1 = [System.Windows.Forms.MessageBox]::Show(
        $msg1, 'Bekreft formatering', 'YesNo', 'Warning')
    if ($confirm1 -ne 'Yes') { return }

    # Bekreftelse 2: tast inn drevbokstaven
    $typed = [Microsoft.VisualBasic.Interaction]::InputBox(
        ("Siste sjekk. Skriv inn drevbokstaven '{0}' for a bekrefte formatering." -f $vol.DriveLetter),
        'Bekreft drevbokstav', '')
    if ($typed.Trim().ToUpper() -ne $vol.DriveLetter.ToString().ToUpper()) {
        $lblStatus.Text = 'Avbrutt: drevbokstav matchet ikke.'
        return
    }

    # Bygg jobb-argument og start formatering i bakgrunnen (holder GUI responsivt)
    if ($doRepartition) {
        $diskNum = (Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction SilentlyContinue).DiskNumber
        $jobArg = @{
            Mode       = 'repartition'
            DiskNumber = $diskNum
            SizeBytes  = ($Fat16PartitionMB * 1MB)
            Fs         = $fsValue
            Label      = $label
        }
        $statusMsg = 'Repartisjonerer disk og lager FAT16 ...'
    }
    else {
        $jobArg = @{
            Mode        = 'format'
            DriveLetter = $vol.DriveLetter
            Fs          = $fsValue
            Label       = $label
            Full        = (-not $quick)
        }
        $statusMsg = ('Formaterer {0}: som {1} ...' -f $vol.DriveLetter, $fsKey)
    }

    $script:ctx = @{ Fs = $fsKey; Repartition = $doRepartition; PartGb = [math]::Round($Fat16PartitionMB / 1024, 1) }

    # Lås UI og vis framdrift
    $btnFormat.Enabled = $false
    $btnRefresh.Enabled = $false
    $cmbDisk.Enabled = $false
    $cmbFs.Enabled = $false
    $progress.Visible = $true
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkBlue
    $lblStatus.Text = $statusMsg

    $jobScript = {
        param($a)
        if ($a.Mode -eq 'repartition') {
            Clear-Disk -Number $a.DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
            $np = New-Partition -DiskNumber $a.DiskNumber -Size $a.SizeBytes -AssignDriveLetter -ErrorAction Stop
            Format-Volume -DriveLetter $np.DriveLetter -FileSystem $a.Fs `
                -NewFileSystemLabel $a.Label -Confirm:$false -Force -ErrorAction Stop | Out-Null
            return [string]$np.DriveLetter
        }
        else {
            $p = @{
                DriveLetter        = $a.DriveLetter
                FileSystem         = $a.Fs
                NewFileSystemLabel = $a.Label
                Confirm            = $false
                Force              = $true
                ErrorAction        = 'Stop'
            }
            if ($a.Full) { $p['Full'] = $true }
            Format-Volume @p | Out-Null
            return [string]$a.DriveLetter
        }
    }

    $script:job = Start-Job -ScriptBlock $jobScript -ArgumentList $jobArg
    $timer.Start()
})

# Timer: poller jobben, oppdaterer GUI ved ferdig/feil
$timer.Add_Tick({
    if (-not $script:job) { $timer.Stop(); return }
    if ($script:job.State -notin @('Completed', 'Failed', 'Stopped')) { return }

    $timer.Stop()
    $err = $null
    $resultLetter = $null
    try {
        $out = Receive-Job -Job $script:job -ErrorAction Stop
        $resultLetter = ($out | Select-Object -Last 1)
    }
    catch { $err = $_.Exception.Message }
    if (-not $err -and $script:job.State -eq 'Failed') { $err = 'Jobben feilet (ukjent årsak).' }
    Remove-Job -Job $script:job -Force
    $script:job = $null

    # Lås opp UI og skjul framdrift
    $progress.Visible = $false
    $btnFormat.Enabled = $true
    $btnRefresh.Enabled = $true
    $cmbDisk.Enabled = $true
    $cmbFs.Enabled = $true

    if ($err) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = ('Feil: {0}' -f $err)
        [System.Windows.Forms.MessageBox]::Show("Formatering feilet:`n`n$err", 'Feil', 'OK', 'Error') | Out-Null
    }
    else {
        if ($script:ctx.Repartition) {
            $doneMsg = ('Ferdig: {0}: ({1} GB) formatert som FAT16. Resten av disken er ubrukt.' -f `
                $resultLetter, $script:ctx.PartGb)
        }
        else {
            $doneMsg = ('Ferdig: {0}: formatert som {1}.' -f $resultLetter, $script:ctx.Fs)
        }
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblStatus.Text = $doneMsg
        [System.Windows.Forms.MessageBox]::Show($doneMsg, 'Fullfort', 'OK', 'Information') | Out-Null
        Update-DiskList
    }
})

# Rydd opp jobb ved lukking
$form.Add_FormClosing({
    $timer.Stop()
    if ($script:job) { Stop-Job $script:job -ErrorAction SilentlyContinue; Remove-Job $script:job -Force -ErrorAction SilentlyContinue }
})

# VisualBasic InputBox brukes til drevbokstav-bekreftelsen
Add-Type -AssemblyName Microsoft.VisualBasic

# Init
Update-DiskList
[void]$form.ShowDialog()
