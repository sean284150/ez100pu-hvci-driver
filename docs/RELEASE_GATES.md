# Release gates

| Version | Required evidence | Public artifacts |
|---|---|---|
| 0.3.x | Clean source audit, CI build, static contracts | Source ZIP, source SBOM, hashes |
| 0.9.x | Frozen source, reproducible build, protocol/stress matrix, HLK candidate results, sponsor review | Source only unless sponsor restricts a private candidate |
| 1.0.0 | Microsoft-returned package, applicable HLK pass, two clean-machine passes, Secure Boot + HVCI on, Test Mode off | Microsoft-signed ZIP, SBOM, hashes, results summary |

No version may skip a gate by disabling Windows security. A successful login on
one machine is recorded as preliminary application evidence, not certification.

Every production rebuild changes the binary and therefore requires a new
Microsoft submission. The signed output, source commit, build log, PDB, SBOM,
HLK package, and SHA-256 manifest must be retained together.
