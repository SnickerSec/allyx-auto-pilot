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
    
    # Fallback URL
    $directDownloadURL = "https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-25.3.1-win10-win11-march-rdna.exe"
    
    try {
        # Configure TLS
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        
        # Try to get URL from website
        $downloadUrl = $directDownloadURL
        
        try {
            Write-Host "Attempting to get latest AMD driver link..." -ForegroundColor Yellow
            $pageContent = $webClient.DownloadString('https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-7-7840u.html')
            
            $pattern = 'href="(https://drivers\.amd\.com/drivers/whql-amd-software.*?\.exe)"'
            if ($pageContent -match $pattern) {
                $downloadUrl = $matches[1]
                Write-Host "Found latest driver URL" -ForegroundColor Green
            }
            else {
                Write-Host "Using fallback URL" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Error parsing AMD website, using fallback URL" -ForegroundColor Yellow
        }
        
        # Download file
        if (Test-URLValid -URL $downloadUrl) {
            $fileName = Split-Path $downloadUrl -Leaf
            $outputPath = Join-Path $downloadDir $fileName
            
            try {
                Write-Host "Downloading $fileName..." -ForegroundColor Yellow
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
            return $null
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        return $null
    }
}

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

# Main script
try {
    Clear-Host
    Write-Host "=== Windows Driver Update Manager ===" -ForegroundColor Cyan
    Write-Host "1. Disable Windows driver updates" -ForegroundColor White
    Write-Host "2. Restore Windows driver updates" -ForegroundColor White
    Write-Host "3. Exit" -ForegroundColor White
    
    $choice = Read-Host "`nEnter your choice (1-3)"
    
    switch ($choice) {
        "1" {
            Disable-WindowsDriverUpdates
            
            $downloadDrivers = Read-Host "`nDownload AMD 7840U drivers? (Y/N)"
            if ($downloadDrivers -eq 'Y' -or $downloadDrivers -eq 'y') {
                $driverPath = Get-AMDDriverDownload
                
                if ($driverPath -and (Test-Path $driverPath)) {
                    $installDrivers = Read-Host "`nInstall the drivers now? (Y/N)"
                    if ($installDrivers -eq 'Y' -or $installDrivers -eq 'y') {
                        Install-AMDDrivers -InstallerPath $driverPath
                    }
                }
            }
        }
        "2" {
            Restore-WindowsDriverUpdates
        }
        "3" {
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit
        }
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
            exit
        }
    }
    
    Write-Host "`nRestart your computer to apply changes" -ForegroundColor Yellow
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
