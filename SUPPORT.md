# Support matrix

| Item | Status |
|---|---|
| Windows 11 x64 build 26100+ | Source target |
| `VID_0CA6&PID_0010&REV_0010` | Exact INF match |
| Memory Integrity (HVCI) | Initial single-machine pass |
| Secure Boot + production signature | Awaiting Microsoft-signed package |
| T=1 / PC/SC | Initial pass |
| T=0 | Not yet hardware-validated |
| Taiwan Labor Insurance login | Initial single-machine pass |
| Tax filing, signing, NHI card, ATM | Not claimed; separate end-to-end gates |
| ARM64 / older Windows / other revisions | Out of scope |

Passing one application login is valuable evidence, but it is not a substitute
for HLK, stress, protocol diversity, independent-machine testing, or a Microsoft
production signature.
