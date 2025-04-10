# allyx-auto-pilot

A PowerShell automation script for managing Windows 11 driver updates and AMD graphics drivers for the Ryzen 7 7840U.

## Features

- Manage Windows 11 automatic driver updates (disable/enable)
- Downloads and installs the latest AMD Ryzen 7 7840U drivers
- Validates download links before attempting downloads
- Provides guided manual driver installation through Device Manager

## Requirements

- Windows 11
- PowerShell with Administrator privileges
- AMD Ryzen 7 7840U processor

## Usage

1. Run PowerShell as Administrator
2. Navigate to the script directory
3. Execute the script:

```powershell
.\allyx_auto_pilot.ps1
```

The script will offer the following options:

1. Disable Windows driver updates
   - Optional: Download and install AMD drivers
2. Restore Windows driver updates
3. Exit

## Important Notes

- A system restart is required after running the script
- Internet connection is required for AMD driver download
- The script validates download links before attempting downloads
- Manual driver update through Device Manager may be necessary
