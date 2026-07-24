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
- Windows generates a local self-signed receiver certificate and renders its SHA-256 fingerprint in the QR pairing payload.
- Android stores approved receiver credentials and the pinned receiver certificate fingerprint in local app preferences.
- Windows persists transfer audit history across receiver restarts.
- Android stores recent transfer records returned by the trusted receiver.
- File uploads use HTTPS with certificate fingerprint pinning and approved device-token authentication after pairing.
- SHA-256 integrity verification.
- `.part` temporary files.
- Windows filename sanitization and duplicate-safe final names.
- File-size limit enforcement before `.part` allocation when `Content-Length` is oversized.
- Structured protocol errors.
- Request rate limiting.
- Available disk-space checks before accepting uploads.

Next security work:

- Upload idle timeouts.
