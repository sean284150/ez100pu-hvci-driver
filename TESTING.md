# Test and stop conditions

## Offline gates (completed for Release x64)

- Warnings-as-errors build.
- InfVerif `/w` succeeds.
- Inf2Cat succeeds with no errors or warnings for Windows 11 25H2 x64.
- PE section/file alignment is 0x1000/0x200; no section is writable and executable.
- NX, ASLR, CFG, high-entropy VA, and image integrity flags are set.

`smclib.sys` is a Microsoft desktop driver interface but is not listed in the Universal/OneCore API set. ApiValidator therefore intentionally classifies this package as Desktop-only. Do not submit it as a Universal driver without replacing smclib integration.

## Live test order

1. Run `Save-Baseline.ps1` elevated while the original driver is active.
2. Build Test, create/trust a local test certificate, sign the SYS and regenerated catalog.
3. Suspend BitLocker protection if required, disable Secure Boot in firmware, enable Test Mode, reboot.
4. Run `Install-TestDriver.ps1` elevated. Confirm Device Manager status `OK`.
5. Test no-card, insertion/removal cancellation, ATR stability, cold/warm reset, T=0/T=1, and representative APDUs.
6. Re-enable Memory Integrity and cold boot. Run `Verify-HVCI.ps1`; inspect Code Integrity events and run Driver Verifier code-integrity checks.
7. On any bugcheck, repeated USB stall, incorrect ATR/APDU, or cancellation hang, run `Restore-Original.ps1` in Safe Mode if necessary.

Do not use the prototype for banking, signing, health-card, or identity transactions until the basic suite passes. The prototype is not WHQL-signed or Microsoft-certified.
