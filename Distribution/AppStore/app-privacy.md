# App Privacy answers (App Store Connect)

Must match `KyAuth/PrivacyInfo.xcprivacy`; change both together.

Data collected: yes.

| Data type | Use | Linked to the user | Tracking |
|---|---|---|---|
| Identifiers → Device ID | App Functionality | Yes | No |
| Identifiers → User ID | App Functionality | Yes | No |

Why: sign-in requests reach the phone through the APNs relay Worker the developer runs
(KyIdentity-server `workers/apns`). The relay receives the phone's APNs token and KyIdentity's
user and device IDs, and keeps tokens beyond the single send. Both are linked to the user because
they are part of signing in.

Not collected: codes and setup keys (encrypted on the phone, never sent), contacts, location,
usage data, diagnostics. Pairing details, the device name and sign-in answers go only to the
KyIdentity server the user's organization runs, not to the developer.
