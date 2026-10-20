# App Privacy answers (App Store Connect)

Must match `KyAuth/PrivacyInfo.xcprivacy`; change both together.

Data collected: yes.

| Data type | Use | Linked to the user | Tracking |
|---|---|---|---|
| Identifiers → Device ID | App Functionality | Yes | No |
| Identifiers → User ID | App Functionality | Yes | No |

Why: sign-in requests reach the phone through the APNs relay Worker the developer runs
(KyIdentity-server `workers/apns`). Every push hands the relay this phone's APNs token. The relay
does not store the raw token, but keeps its SHA-256 hash with the sending KyIdentity server's relay
key ID for as long as the token stays claimed, so the token is collected, not ephemeral (Device ID).

A pairing made by this app registers RFC 8291 push keys, and KyIdentity then seals the challenge:
the relay and Apple see only the APNs token, the fixed alert text, `type` and the ciphertext
`kyauth`, with no KyIdentity user, device or challenge ID. User ID stays declared because the
plaintext path still exists: a pairing without push keys (made before KyAuth sent them, or
refreshed without them; KyIdentity accepts both) gets `challengeId`, `deviceId`, `deviceUserId`,
`purpose`, `expiresAtEpochMs` and `devicePlatform` in the clear, through the relay and Apple. Drop
the User ID row only when no shipped build or server can produce such a pairing.

Both are linked to the user because they are part of signing in.

Not collected: codes and setup keys (encrypted on the phone, never sent), contacts, location,
usage data, diagnostics. Pairing details, the device name and sign-in answers go only to the
KyIdentity server the user's organization runs, not to the developer.
