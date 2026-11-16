# Troubleshooting

- **App cannot create a vault:** confirm that the device has a passcode and that device authentication works.
- **No push notification:** check notification permission, connectivity and the server's APNs configuration. Simulator success cannot prove physical-device push delivery.
- **TOTP rejected:** check automatic date/time and the service's setup parameters.
- **Unreadable vault error:** preserve the existing data and investigate; an unreadable vault is not an empty vault.
- **Lost phone or exhausted PIN attempts:** use service recovery codes and revoke the old KyIdentity device. There is no vault export or cloud restore.

When reporting a problem, include the product version, platform, failed task and a redacted error. Exclude pairing links, device secrets, recovery codes, custodian shares and private content.
