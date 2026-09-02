# Security policy

## Supported versions

No production-supported release exists yet. Security fixes are applied to the
latest 0.3.x source preview until a Microsoft-signed 1.0.0 is published.

## Reporting

Do not post card data, APDUs, PINs, certificates, crash dumps, ETL traces, or
machine baselines in a public issue. Open a minimal issue containing only the
driver version, Windows build, exact USB hardware ID, and a description that
contains no personal data. A private reporting channel will be added before
the first public release.

The driver diagnostics must never log APDU payloads, PINs, card certificate
content, or authentication material. Logs are limited to stable stage/status
codes, lengths, sequence numbers, and transport state.

## Release trust

Only a package returned by Microsoft from the Hardware Developer Program may be
published as installable production media. Test certificates, EV private keys,
and signing tokens must never be committed or uploaded to GitHub Actions.
