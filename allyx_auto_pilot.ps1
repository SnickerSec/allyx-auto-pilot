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
        $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        $request.Referer = "https://www.amd.com/"
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
        [System.Net.ServicePointManager]::DnsRefreshTimeout = 0
        [System.Net.ServicePointManager]::EnableDnsRoundRobin = $true

        # Try up to 3 times
        $maxRetries = 3
        $retryCount = 0
        $success = $false
        $pageContent = $null
        $baseTimeout = 30  # Base timeout in seconds
        
        while (-not $success -and $retryCount -lt $maxRetries) {
            $retryCount++
            $currentTimeout = $baseTimeout * $retryCount  # Progressive timeout
            
            try {
                Write-Host "Attempt $retryCount of $maxRetries`: Searching for WHQL Recommended driver..." -ForegroundColor Yellow
                
                # Test DNS resolution first
                try {
                    $dnsResult = [System.Net.Dns]::GetHostEntry("www.amd.com")
                    Write-Host "DNS Resolution successful: $($dnsResult.AddressList[0])" -ForegroundColor Green
                }
                catch {
                    Write-Host "DNS Resolution failed: $_" -ForegroundColor Red
                }
                
                $url = 'https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-7-7840u.html'
                
                # Special headers that need to be set via properties
                $specialHeaders = @{
                    "UserAgent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                    "Accept"    = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
                    "Referer"   = "https://www.amd.com/"
                    "Host"      = "www.amd.com"
                }
                
                # Regular headers that can be set via Headers collection
                $headers = @{
                    "Accept-Language"           = "en-US,en;q=0.9"
                    "Cache-Control"             = "no-cache"
                    "sec-ch-ua"                 = "`"Not_A Brand`";v=`"8`", `"Chromium`";v=`"120`""
                    "sec-ch-ua-mobile"          = "?0"
                    "sec-ch-ua-platform"        = "`"Windows`""
                    "Sec-Fetch-Dest"            = "document"
                    "Sec-Fetch-Mode"            = "navigate"
                    "Sec-Fetch-Site"            = "same-origin"
                    "Sec-Fetch-User"            = "?1"
                    "Upgrade-Insecure-Requests" = "1"
                }

                # Configure request
                [System.Net.ServicePointManager]::Expect100Continue = $false
                $request = [System.Net.WebRequest]::Create($url)
                
                # Set special headers via properties
                $request.UserAgent = $specialHeaders["UserAgent"]
                $request.Accept = $specialHeaders["Accept"]
                $request.Referer = $specialHeaders["Referer"]
                $request.Host = $specialHeaders["Host"]
                
                # Set regular headers via Headers collection
                foreach ($header in $headers.GetEnumerator()) {
                    $request.Headers[$header.Key] = $header.Value
                }
                
                $request.Timeout = $currentTimeout * 1000
                $request.AllowAutoRedirect = $true
                
                Write-Host "`nConnection Settings:" -ForegroundColor Cyan
                Write-Host "Timeout: $currentTimeout seconds" -ForegroundColor Yellow
                Write-Host "Using Proxy: $([System.Net.WebRequest]::DefaultWebProxy.GetProxy($url))" -ForegroundColor Yellow

                Write-Host "`nRequest Details:" -ForegroundColor Cyan
                Write-Host "URL: $url" -ForegroundColor Yellow
                Write-Host "Headers:" -ForegroundColor Yellow
                $headers.GetEnumerator() | ForEach-Object {
                    Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
                }

                $startTime = Get-Date
                Write-Host "`nSending request at $startTime..." -ForegroundColor Yellow
                
                $ProgressPreference = 'SilentlyContinue'  # Disable progress bar for better performance
                $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec $currentTimeout -MaximumRedirection 5 -Verbose
                $endTime = Get-Date
                $duration = ($endTime - $startTime).TotalSeconds
                
                Write-Host "`nResponse Details:" -ForegroundColor Cyan
                Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor Yellow
                Write-Host "Status Description: $($response.StatusDescription)" -ForegroundColor Yellow
                Write-Host "Time Taken: $duration seconds" -ForegroundColor Yellow
                Write-Host "`nResponse Headers:" -ForegroundColor Yellow
                $response.Headers.GetEnumerator() | ForEach-Object {
                    Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
                }
                
                $pageContent = $response.Content
                $success = $true
            }
            catch [System.Net.WebException] {
                $errorResponse = $_.Exception.Response
                Write-Host "`nWeb Exception Details:" -ForegroundColor Red
                Write-Host "Status: $($_.Exception.Status)" -ForegroundColor Red
                Write-Host "Message: $($_.Exception.Message)" -ForegroundColor Red
                if ($errorResponse) {
                    Write-Host "Response Status: $($errorResponse.StatusCode.value__) $($errorResponse.StatusDescription)" -ForegroundColor Red
                }
                throw
            }
            catch {
                Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
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
                
                try {
                    # Continue with download process
                    if (Test-URLValid -URL $downloadUrl) {
                        $fileName = Split-Path $downloadUrl -Leaf
                        $outputPath = Join-Path $downloadDir $fileName
                        
                        Write-Host "Downloading $fileName..." -ForegroundColor Yellow
                        $webClient = New-Object System.Net.WebClient
                        $webClient.Headers.Add("Referer", "https://www.amd.com/")
                        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                        $webClient.DownloadFile($downloadUrl, $outputPath)
                        Write-Host "Download complete: $outputPath" -ForegroundColor Green
                        return $outputPath
                    }
                    else {
                        throw "Download URL validation failed"
                    }
                }
                catch {
                    Write-Host "Download failed: $_" -ForegroundColor Red
                    Write-Host "Opening AMD download page in browser..." -ForegroundColor Yellow
                    Start-Process "https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-7-7840u.html"
                    return $null
                }
                finally {
                    if ($webClient) {
                        $webClient.Dispose()
                    }
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
