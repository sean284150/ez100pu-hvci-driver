# Production signing / WHCP checklist

- Keep neutral compatibility branding in source; record the legal organization that owns the final Hardware Dashboard submission.
- Have that organization register in Microsoft Partner Center / Hardware Dev Center using its legal contact and EV code-signing certificate.
- Build from a clean, version-tagged source tree with the pinned VS 2022, SDK 10.0.26100.0, and KMDF 1.35 toolchain.
- Run Static Driver Verifier, CodeQL/driver static analysis as applicable, Driver Verifier (including Code Integrity), Device Fundamentals, USB, PnP/power, and Smart Card reader HLK tests on supported Windows 11 releases.
- Test suspend/resume, surprise removal, cancellation, malformed/short USB responses, stalls, timeout recovery, T=0/T=1 cards, and long-duration insertion/removal loops.
- Submit the signed HLK package and retain the Microsoft-returned package, HLK logs, symbol files, source revision, reproducible build log, SBOM, license/clean-room record, and release SHA-256 manifest.
- Do not use “WHQL”, “Microsoft certified”, or “Windows 11 certified” until the returned Microsoft-signed package and applicable certification have actually been obtained.

See `docs/HLK_MATRIX.md`, `docs/SIGNING_SPONSOR.md`, and
`docs/RELEASE_GATES.md`. If no qualified sponsor is available, releases remain
source-only; Test Mode is not a production fallback.
