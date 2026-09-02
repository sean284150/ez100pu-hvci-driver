# Validation record — 2026-09-02

Target: Windows 11 Enterprise x64 25H2 build 26200.9168; hardware ID
`USB\VID_0CA6&PID_0010&REV_0010`.

## Historical prototype evidence

- Prototype version 0.2.5.0 was installed locally during the initial research.
- Test package is signed by the locally trusted `EZ100PU HVCI Prototype Test`
  certificate. It is not WHQL or Microsoft production signed.
- Debug, Test, and Release x64 builds passed with warnings as errors.
- InfVerif `/w` and Inf2Cat `/os:10_25H2_X64` passed with no errors or warnings.
- PE section alignment is `0x1000`; no section is writable and executable.
- NX, ASLR, CFG, high-entropy VA, and image-integrity flags are enabled.
- Desktop-only classification is intentional because Microsoft `smclib` exports
  are not in the Universal/OneCore API set.

## Live functional results

- Device Manager/PnP status: `OK`, problem code 0.
- Driver service `ez100pu_kmdf`: Running.
- Smart Card Resource Manager `SCardSvr`: Running.
- Empty-reader state: `Present=False`, `Empty=True`, not unavailable or mute.
- Card insertion and a stable ATR were detected. The ATR is omitted from this
  public record.
- PPS negotiation: card TA1 `0x96` was reduced to reader-compatible `0x95`
  before CCID parameter switching.
- PC/SC connection selected T=1 successfully.
- A non-identifying GET CHALLENGE transport test completed through
  `SCardTransmit`; the card returned a valid status word (`6E00` or `6986`).
  Response data was not logged.
- Card removal returned to the correct empty-reader state.
- No stage 40, 41, or 42 transport/protocol failures and no Smart Card event
  610 occurred during the final insertion, APDU, and removal sequence.
- User-reported end-to-end validation: Taiwan Labor Insurance online login
  authentication completed successfully with the prototype active and HVCI
  running. No account, certificate, PIN, or response content was recorded.

## HVCI results

- Memory Integrity was configured without UEFI lock and verified after reboot.
- `Win32_DeviceGuard.SecurityServicesRunning` contained service 2: HVCI was
  actually running, not merely enabled in the registry.
- With HVCI running, driver `0.2.5.0` loaded, remained `OK`,
  and passed empty, insertion, ATR, T=1 connection, APDU, and removal tests.
- Relevant Code Integrity events for `ez100pu_kmdf`, `ezusb64`, and event IDs
  3033/3077/3089/3111 after the HVCI boot: zero.

## Recovery and remaining scope

The original vendor package remained backed up outside the public source tree
and was not deleted. Local-only recovery scripts restore the original
package/settings and turn off Test Mode after prototype testing.

Not yet completed: Driver Verifier stress, HLK HVCI Readiness, suspend/resume,
extended unplug/replug and stall injection, T=0 with a suitable card,
health-card software, ATM/banking, tax filing, or signing workflows. These
remain outside the acceptance recorded here. One real online identity-login
path has passed, but this is not a general certification of every HiCOS or
smart-card application.

## Version 0.3.0 offline evidence

- Main smclib dispatch is serialized.
- CCID framing is factored into host-tested C code, including short, malformed,
  wrong-sequence, time-extension, command-failure, and capacity cases.
- Time-extension exhaustion returns timeout and resets the transport.
- Fi/Di selection searches the WDK-provided ISO tables instead of decrementing
  indexes, and diagnostics no longer contain transmitted bytes.
- Release x64 warnings-as-errors build, InfVerif, Inf2Cat, PE mitigation checks,
  and static contracts pass locally.
- Two consecutive clean Release rebuilds produced the same SYS SHA-256.
- The legacy Visual Studio `/analyze` pass currently reports WDK-header
  annotation diagnostics in addition to project diagnostics and is not counted
  as passed; GitHub CodeQL and the WHCP analysis requirements remain release
  gates.

No 0.3.0 live-card, Driver Verifier, HLK, second-machine, or Microsoft-signing
claim is made yet.

### 0.3.0 no-card live check

- Installed locally as a test-signed package while Memory Integrity remained
  running in the existing development configuration.
- PnP status was `OK`; PC/SC reported `Present=False`, `Empty=True`,
  `Unavailable=False`, and `Mute=False`.
- No matching Code Integrity block event appeared in the ten-minute installation
  window.
- The card was intentionally absent, so this check makes no ATR, PPS, T=0/T=1,
  APDU, or application-login claim for 0.3.0.
