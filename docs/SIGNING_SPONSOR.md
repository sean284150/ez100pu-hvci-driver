# Production-signing sponsor requirements

The preferred order is Castles Technology or an authorized Taiwan channel,
then an established open-source organization already enrolled in Microsoft's
Hardware Developer Program, then a qualified nonprofit signing program, and
finally a paid WHQL lab or submission partner.

A sponsor must:

- Be a verifiable legal organization and identify the Hardware Dashboard owner.
- Review the public source and reproduce the exact candidate binary.
- Submit through its own Hardware Dashboard account and return the unmodified
  Microsoft-signed package plus submission evidence.
- Agree on vulnerability intake, revocation, rebuild, and support ownership.
- Never share an EV private key or ask the project to use a borrowed certificate.

OSSign is an outreach lead only. It is not considered a solution until it
confirms that it can perform the Microsoft Hardware Dashboard/WHCP submission
for this kernel driver and applications are open.

The project does not require Windows Update distribution. A Microsoft-signed
package may be distributed through GitHub after its source/build/test linkage
has been verified.
