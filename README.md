# EZ100PU compatible driver for Windows 11

An independent, clean-room Windows smart-card reader driver for the exact device
`USB\VID_0CA6&PID_0010&REV_0010`. The project exists to replace a legacy driver
that cannot load with Windows Memory Integrity (HVCI).

This project is not affiliated with, endorsed by, or supported by Castles
Technology. “EZ100PU” is used only to identify compatible hardware.

## Current status

Version 0.3.x is a source preview. It builds as a Windows 11 x64 KMDF desktop
driver using Microsoft `smclib`, supports the reader's observed CCID-like USB
transport, and has passed an initial T=1 PC/SC login test on one development
computer with HVCI running. T=0, extended stress, HLK, independent-machine, and
Microsoft production-signing gates remain open.

There is intentionally no public installable binary before Microsoft signs an
accepted production submission. Do not disable Secure Boot, enable Test Mode,
or turn off Memory Integrity to install a release from this repository.

## Supported target

- Windows 11 x64 build 26100 or later.
- Exact hardware revision `USB\VID_0CA6&PID_0010&REV_0010` only.
- Desktop driver model; this is not a Universal/OneCore driver.

Other EZ100PU revisions and ARM64 are deliberately not matched by the INF.

## Build

Install Visual Studio 2022 Build Tools, Windows 11 SDK/WDK 10.0.26100.0, and
KMDF 1.35. In an ordinary PowerShell session run:

```powershell
.\scripts\Assert-Toolchain.ps1
.\scripts\Build-Package.ps1 -Configuration Release
.\tests\Static-Contract.Tests.ps1
```

The build is warnings-as-errors. Generated SYS, CAT, PDB, logs, certificates,
and local hardware captures are excluded from source control.

## Installation

The production scripts in `release/` accept only a Microsoft kernel-policy
signed package. They do not change Secure Boot, Test Mode, HVCI, or BitLocker.
Until a Microsoft-signed package exists, these scripts are a reviewed release
interface rather than an installation path for ordinary users.

See `TESTING.md`, `SUBMISSION.md`, `SECURITY.md`, and `CLEANROOM.md` before
testing or contributing.

## License

MIT. See `LICENSE.txt` and `THIRD_PARTY_NOTICES.md`.
