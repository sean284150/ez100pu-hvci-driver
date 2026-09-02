# HLK and hardware validation matrix

Use the HLK release, playlist, filters, and supplemental content applicable to
the supported Windows 11 release. Preserve the `.hlkx` package without editing
test results.

## Required groups

- Device Fundamentals and applicable SmartCardReader tests.
- USB descriptor, transfer, reliability, and device-removal tests.
- PnP start/stop/rebalance, surprise removal, disable/enable, and restart.
- Sleep, hibernate, modern standby where available, resume, and cold boot.
- Driver Verifier: Code Integrity, I/O verification, pool, PnP/power, and DDI
  compliance using Microsoft-recommended settings for the target build.
- Concurrent PC/SC clients, canceled card-state waits, and repeated insert/remove.

## Card/application matrix

- At least one confirmed T=0 card and one confirmed T=1 card.
- Taiwan citizen certificate/HiCOS representative card.
- Non-identifying PC/SC connect, reset, ATR, protocol, and benign APDU checks.
- Taiwan Labor Insurance login regression.
- Tax, signing, NHI, and ATM flows remain unsupported until each has a separate
  successful, consented end-to-end result and no sensitive payload is captured.

## Clean-machine gate

Run on at least two non-development Windows 11 x64 computers with build 26100+
and the exact REV_0010 reader. Secure Boot and Memory Integrity must be running,
Test Mode must be off, and the test certificate must never have been installed.
Validate install, cold boot, PC/SC operation, removal, rollback, and Code
Integrity logs.
