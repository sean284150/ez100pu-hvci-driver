# Clean-room record

This implementation was written from public interface specifications and observed device behavior. No Castles binary was decompiled, transformed, patched, or redistributed. The LGPL ezIFD project was used only to identify externally observable wire quirks; none of its implementation code was copied.

Protocol facts implemented here: vendor-class USB interface; bulk OUT 0x01, bulk IN 0x82, interrupt IN 0x83; CCID-shaped 10-byte messages; device-specific big-endian `dwLength`; an extra zero preceding the ATR; synthetic limits (one slot, T=0/T=1, TPDU exchange, maximum message 271 bytes). The driver bounds the transport buffer to 512 bytes.

Primary references:

- USB-IF, *USB Integrated Circuit(s) Cards Interface Devices, Revision 1.1*.
- Microsoft Windows Driver Samples, `smartcrd/pscr`, for the documented Smart Card Driver Library integration pattern.
- Microsoft WDK headers and documentation for `smclib`, KMDF, WDFUSB, and smart-card IOCTL contracts.

The Microsoft sample repository is MIT-licensed. This prototype keeps the same license for the newly written and sample-derived integration code.

## Protocol-selection correction (0.2.4)

The card observed during testing advertises TA1 `0x96`, whose requested data
rate exceeds the reader's advertised 115200-bit/s maximum. Version 0.2.4
performs the ISO/IEC 7816-3 PPS request/confirmation before changing the CCID
parameters and selects the fastest lower D index within that limit (`0x95`).
Only standardized PPS framing and observable device capabilities were used;
no third-party source code was copied.

## Production-hardening correction (0.3.0)

The PPS rate selection now evaluates the WDK-provided ISO Fi/Di tables instead
of assuming that adjacent D indexes represent progressively slower rates. It
caps the selection at both the card-requested rate and the reader-advertised
maximum, and uses an ISO default-rate fallback only after a protocol-level PPS
rejection. Transport failures are not converted into negotiation fallback.

The CCID time-extension limit now terminates with a timeout and pipe recovery;
it cannot treat the response beyond the configured limit as a successful data
block. Diagnostic records contain protocol identifiers, lengths, state, and
status only—never APDU or PIN bytes.
