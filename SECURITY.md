# Security policy

## Supported use

This project is a compatibility port of a deprecated scripting engine. It is
intended for trusted application scripts required by existing Qt applications.

The embedded JavaScriptCore snapshot dates from 2011 and does not receive the
security maintenance of a current JavaScript runtime. Do not expose it to
untrusted scripts, documents, plug-ins, or network-provided content, and do not
treat it as a sandbox or security boundary.

The qmc2 maintenance branch preserves this legacy engine specifically for
trusted qchdman automation and debugger compatibility. Source ownership does
not make the engine suitable for processing untrusted input.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository rather
than opening a public issue with exploit details.
