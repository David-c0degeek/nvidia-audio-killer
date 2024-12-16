# NVIDIA Audio Control

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![PowerShell](https://img.shields.io/badge/PowerShell-%235391FE.svg?style=flat&logo=powershell&logoColor=white)
![Windows 11](https://img.shields.io/badge/Windows%2011-0078D4?style=flat&logo=windows11&logoColor=white)

## Overview

A PowerShell solution to permanently prevent NVIDIA High Definition Audio devices from being automatically enabled in Windows. This script creates a persistent monitor that automatically disables NVIDIA audio devices when they appear, ensuring your audio output remains on your preferred device.

### Features

- 🔄 Automatic disable of NVIDIA HD Audio devices
- 🕒 Persistent monitoring across system restarts
- 📝 Comprehensive logging system
- 🛡️ Error resilient with retry mechanisms
- 🖥️ User-friendly interactive menu
- 🚀 One-line installation option

## Quick Start

### One-Line Installation

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/C0deGeek/nvidia-audio-control/main/killaudio.ps1 | iex
```

This command will:
1. Temporarily bypass execution policy for the current PowerShell session
2. Download and execute the script
3. Install the audio control service

### Manual Installation

1. Clone the repository:
```powershell
git clone https://github.com/C0deGeek/nvidia-audio-control.git
```

2. Navigate to the script directory:
```powershell
cd nvidia-audio-control
```

3. Run the script:
```powershell
.\killaudio.ps1
```

## Usage

### Interactive Menu Options

1. **Install and enable audio control**
   - Sets up the monitoring service
   - Creates necessary scheduled tasks
   - Performs initial device check

2. **Uninstall and disable audio control**
   - Removes all components
   - Cleans up scheduled tasks
   - Deletes script files

3. **Check current status**
   - Shows service status
   - Displays last run time
   - Lists current NVIDIA audio devices

4. **View logs**
   - Shows the last 20 log entries
   - Useful for troubleshooting

5. **Force immediate device check**
   - Manually triggers device scan
   - Disables any found NVIDIA audio devices

### Script Location

After installation, components are stored in:
- Scripts: `C:\DeviceAudioAutoDisable\`
- Logs: `C:\DeviceAudioAutoDisable\AudioControl.log`

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- Administrator privileges
- NVIDIA Graphics Card (for the script to be useful)

## Troubleshooting

### Common Issues

1. **Script won't run**
   - Ensure you have administrator privileges
   - Check execution policy
   - Verify PowerShell version

2. **Devices still appearing**
   - Check logs for errors
   - Verify service is running
   - Run immediate device check

3. **Installation fails**
   - Ensure you have admin rights
   - Check system permissions
   - Review logs for specific errors

### Logging

Logs are stored at `C:\DeviceAudioAutoDisable\AudioControl.log` and contain:
- Timestamp for each action
- Success/failure status
- Error details when applicable
- Device state changes

## Uninstallation

To remove the script and all its components:

1. Run the script interactively:
```powershell
.\killaudio.ps1
```

2. Select option 2 (Uninstall and disable audio control)

Or use PowerShell directly:
```powershell
Unregister-ScheduledTask -TaskName "NvidiaAudioAutoDisable" -Confirm:$false
Remove-Item "C:\DeviceAudioAutoDisable" -Recurse -Force
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**David (C0deGeek)**

## Acknowledgments

- NVIDIA for consistently giving us reasons to write scripts like this
- The PowerShell community for their invaluable resources and support

---

For support, please [open an issue](https://github.com/C0deGeek/nvidia-audio-control/issues) on GitHub.
