#Requires -RunAsAdministrator

function Test-URLValid {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$URL
    )

    $response = $null
    try {
        $request = [System.Net.WebRequest]::Create($URL)
        $request.Method = "HEAD"
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $statusCode = [int]$response.StatusCode
        return $statusCode -eq 200
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $response) {
            $response.Close()
        }
    }
}

function Get-AMDDriverDownload {
    [CmdletBinding()]
    param ()

    $downloadDir = "$env:USERPROFILE\Downloads\AMD_Drivers"
    if (!(Test-Path $downloadDir)) {
        New-Item -Path $downloadDir -ItemType Directory | Out-Null
    }

    Write-Host "Downloading latest AMD 7840U drivers..." -ForegroundColor Yellow
    
    try {
        # Configure TLS and connection settings
        [System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [System.Net.ServicePointManager]::DefaultConnectionLimit = 100

        # Try up to 3 times
        $maxRetries = 3
        $retryCount = 0
        $success = $false
        $pageContent = $null

        while (-not $success -and $retryCount -lt $maxRetries) {
            $retryCount++
            try {
                Write-Host "Attempt $retryCount of $maxRetries`: Searching for WHQL Recommended driver..." -ForegroundColor Yellow
                
                $request = [System.Net.WebRequest]::Create('https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-7-7840u.html')
                $request.Timeout = 30000 # 30 seconds
                $request.UserAgent = "Mozilla/5.0"
                
                $response = $request.GetResponse()
                $stream = $response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $pageContent = $reader.ReadToEnd()
                $success = $true
                
                $reader.Close()
                $stream.Close()
                $response.Close()
            }
            catch {
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Attempt failed, retrying in 5 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 5
                }
            }
        }

        if ($success) {
            Write-Host "Parsing page content for driver information..." -ForegroundColor Yellow
            
            # Find section containing "WHQL Recommended"
            if ($pageContent -match '<p>Adrenalin [^<]+ \(WHQL Recommended\)</p>[\s\S]*?<a href="([^"]+)"[^>]*>[\s\S]*?Download') {
                $downloadUrl = $matches[1]
                Write-Host "`nParsed Download Information:" -ForegroundColor Cyan
                Write-Host "Full Match: $($matches[0])" -ForegroundColor Yellow
                Write-Host "Extracted URL: $downloadUrl" -ForegroundColor Green
                
                # Continue with download process
                if (Test-URLValid -URL $downloadUrl) {
                    $fileName = Split-Path $downloadUrl -Leaf
                    $outputPath = Join-Path $downloadDir $fileName
                    
                    try {
                        Write-Host "Downloading $fileName..." -ForegroundColor Yellow
                        $webClient = New-Object System.Net.WebClient
                        $webClient.DownloadFile($downloadUrl, $outputPath)
                        Write-Host "Download complete: $outputPath" -ForegroundColor Green
                        return $outputPath
                    }
                    catch {
                        Write-Host "Download failed: $_" -ForegroundColor Red
                        return $null
                    }
                }
                else {
                    Write-Host "Download URL not accessible" -ForegroundColor Red
                    Write-Host "Opening AMD download page in browser..." -ForegroundColor Yellow
                    Start-Process "https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-7-7840u.html"
                    return $null
                }
            }
            else {
                Write-Host "`nDebug Information:" -ForegroundColor Cyan
                Write-Host "Could not find WHQL Recommended driver pattern in page content" -ForegroundColor Red
                Write-Host "Page Content Sample:" -ForegroundColor Yellow
                Write-Host ($pageContent -replace '(?s)^.{0,500}(.{0,1000}).*', '$1') -ForegroundColor Gray
                Write-Host "Opening AMD download page in browser..." -ForegroundColor Yellow
                Start-Process "https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-7-7840u.html"
                return $null
            }
        }
        else {
            Write-Host "`nAutomatic download failed after $maxRetries attempts." -ForegroundColor Red
            Write-Host "Opening AMD download page in browser..." -ForegroundColor Yellow
            Start-Process "https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-7-7840u.html"
            
            # Allow manual path input
            Write-Host "`nOnce you've downloaded the driver manually:" -ForegroundColor Cyan
            Write-Host "1. Save it to: $downloadDir" -ForegroundColor White
            Write-Host "2. Or enter the full path to the downloaded file below" -ForegroundColor White
            
            $manualPath = Read-Host "`nEnter the path to the downloaded driver (or press Enter to skip)"
            if (![string]::IsNullOrEmpty($manualPath) -and (Test-Path $manualPath)) {
                return $manualPath
            }
            return $null
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        return $null
    }
} # Add missing closing brace here

function Install-AMDDrivers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath
    )
    
    try {
        Write-Host "Running AMD driver installer..." -ForegroundColor Yellow
        Start-Process -FilePath $InstallerPath -Wait
        Write-Host "Installation complete" -ForegroundColor Green
        
        Write-Host "Launching Device Manager..." -ForegroundColor Yellow
        Start-Process "devmgmt.msc"
        
        Write-Host "`nUpdate Graphics Driver Manually:" -ForegroundColor Cyan
        Write-Host "1. Expand 'Display adapters'" -ForegroundColor White
        Write-Host "2. Right-click AMD Graphics" -ForegroundColor White
        Write-Host "3. Select 'Update driver'" -ForegroundColor White
        Write-Host "4. Browse computer for drivers" -ForegroundColor White
        Write-Host "5. Select from driver list" -ForegroundColor White
        Write-Host "6. Choose newest AMD driver" -ForegroundColor White
    }
    catch {
        Write-Host "Installation error: $_" -ForegroundColor Red
    }
}

function Disable-WindowsDriverUpdates {
    [CmdletBinding()]
    param ()
    
    Write-Host "Disabling Windows driver updates..." -ForegroundColor Yellow

    # Registry modifications
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" /v "SearchOrderConfig" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" /v "PreventDeviceMetadataFromNetwork" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "ExcludeWUDriversInQualityUpdate" /t REG_DWORD /d 1 /f

    # PowerShell registry path
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (!(Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord

    Write-Host "Windows driver updates disabled" -ForegroundColor Green
}

function Restore-WindowsDriverUpdates {
    [CmdletBinding()]
    param ()
    
    Write-Host "Restoring Windows driver updates..." -ForegroundColor Yellow

    # Registry modifications
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" /v "SearchOrderConfig" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" /v "PreventDeviceMetadataFromNetwork" /t REG_DWORD /d 0 /f
    reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "ExcludeWUDriversInQualityUpdate" /f

    Write-Host "Windows driver updates restored" -ForegroundColor Green
}

function Install-AMDDriverComplete {
    [CmdletBinding()]
    param ()
    
    $downloadDrivers = Read-Host "`nDownload AMD 7840U drivers? (Y/N)"
    if ($downloadDrivers -ne 'Y' -and $downloadDrivers -ne 'y') {
        return
    }
    
    $driverPath = Get-AMDDriverDownload
    if (-not $driverPath -or -not (Test-Path $driverPath)) {
        return
    }
    
    $installDrivers = Read-Host "`nInstall the drivers now? (Y/N)"
    if ($installDrivers -eq 'Y' -or $installDrivers -eq 'y') {
        Install-AMDDrivers -InstallerPath $driverPath
    }
}

# Main script
Clear-Host
Write-Host "=== Windows Driver Update Manager ===" -ForegroundColor Cyan
Write-Host "1. Disable Windows driver updates" -ForegroundColor White
Write-Host "2. Restore Windows driver updates" -ForegroundColor White
Write-Host "3. Exit" -ForegroundColor White
    
$choice = Read-Host "`nEnter your choice (1-3)"
    
switch ($choice) {
    "1" { 
        Disable-WindowsDriverUpdates
        Install-AMDDriverComplete
    }
    "2" { 
        Restore-WindowsDriverUpdates 
    }
    "3" { 
        Write-Host "Exiting..." -ForegroundColor Yellow
        return
    }
    default {
        Write-Host "Invalid choice" -ForegroundColor Red
        return
    }
}

Write-Host "`nRestart your computer to apply changes" -ForegroundColor Yellow
