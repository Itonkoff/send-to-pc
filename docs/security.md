# Security

The receiver never accepts file uploads without a bearer token. The current checkpoint keeps a visible in-memory bootstrap token for local upload testing, and it never persists that token. Real pairing requests create per-device tokens only after explicit Windows approval.

Implemented now:

- Bearer-token authentication for transfer routes.
- Constant-time token comparison.
- Secure random token generation.
- Short-lived pairing sessions and one-time pairing token validation.
- Explicit approve/reject UI for pairing requests.
- Persisted trusted-device records on Windows.
- Windows can revoke trusted devices so their bearer tokens stop authenticating.
- Windows renders the active pairing payload as a QR code for Android scanning.
- Android stores approved receiver credentials in local app preferences.
- Windows persists transfer audit history across receiver restarts.
- Android stores recent transfer records returned by the trusted receiver.
- File uploads authenticated by approved device tokens after pairing.
- SHA-256 integrity verification.
- `.part` temporary files.
- Windows filename sanitization and duplicate-safe final names.
- File-size limit enforcement before `.part` allocation when `Content-Length` is oversized.
- Structured protocol errors.

Next security work:

- HTTPS with certificate fingerprint pinning.
- Request rate limiting and upload timeouts.