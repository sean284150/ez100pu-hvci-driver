# Contributing

Contributions must preserve the clean-room boundary. Do not submit decompiled
or transformed vendor binaries, proprietary source, copied LGPL implementation
code, original driver packages, card dumps, or private user traces.

Every change must build with warnings treated as errors and include a focused
test or a written explanation of the hardware-only verification required. Code
affecting USB framing, ATR/PPS negotiation, T=0/T=1, cancellation, PnP, or power
management requires review by a maintainer and hardware validation before it is
eligible for a signed release.

Use neutral compatibility wording. Never describe this implementation as an
official Castles Technology or Microsoft driver.
