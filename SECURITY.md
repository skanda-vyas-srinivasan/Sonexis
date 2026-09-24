# Security policy

## Supported versions

Security fixes are made against the latest released version and the current default branch. Older releases may not receive separate patches.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use GitHub's private vulnerability reporting feature from the repository's **Security** tab. If that feature is unavailable, contact the maintainer through the private contact channel listed at [sonexis.ink](https://sonexis.ink).

Include:

- the affected version or commit;
- macOS and hardware details;
- exact reproduction steps or a minimal proof of concept;
- the expected and observed security boundary;
- potential impact and any known mitigations.

Avoid accessing other people's data, disrupting services, or publishing exploit details before a fix is available. Reports will be acknowledged when received, investigated based on severity and reproducibility, and credited when desired.

## Scope notes

Sonexis captures system audio with user-granted macOS permission and hosts third-party Audio Units in process. A permission prompt, expected local plug-in execution, or a source-level concern without a demonstrated boundary failure is not by itself a vulnerability. Crashes from untrusted preset/workspace data, unintended capture, privilege-boundary failures, and unauthorized data exposure are in scope.
