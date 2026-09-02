# Third-party notices

The driver integrates with Microsoft Windows Driver Kit interfaces, including
KMDF, WDFUSB, and the Windows Smart Card Driver Library (`smclib`).

The dispatch architecture was informed by Microsoft's `smartcrd/pscr` sample
from the Windows Driver Samples repository, which is published under the MIT
License. USB CCID behavior is based on the public USB-IF CCID specification.

The public LGPL ezIFD project was consulted only as a description of externally
observable device quirks. No ezIFD source code is copied into this repository.

Castles Technology and EZ100PU names and identifiers belong to their respective
owners and are used only to state hardware compatibility.
