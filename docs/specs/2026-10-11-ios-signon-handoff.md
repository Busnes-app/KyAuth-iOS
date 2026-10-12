# KyAuth iOS: KyIdentity sign-on handoff to suite apps

Status: approved direction (user, 2026-10-11: "app-to-app handoff; KyPost-for-Mac needs a rebuild").
Replaces Android's `AccountManager` authenticator on iOS. Contract between KyAuth iOS and its
consumers; KyPost iOS (`KyPost-for-Mac`, iOS target) is the first.

## Trust model

Android pins each consumer by package and signing certificate. iOS has no caller identity on a
URL open, and any app may claim a URL scheme. The handoff therefore never puts a request or a
token in a URL. Both travel through the shared App Group container
`group.org.kysecurity.signon`, which only apps provisioned by team `TATYN4X57D` can open. The team
is the trust domain: a consumer is any app of that team listed in KyAuth's `TrustedConsumers`.
URLs carry only a single-use nonce.

## Files

Inside the group container, under `SignOn/`, all with `FileProtectionType.complete`:

- `requests/<nonce>.json`: written by the consumer, read and deleted by KyAuth.
- `responses/<nonce>.json`: written by KyAuth, read and deleted by the consumer.

`nonce` is 32 random bytes, base64url without padding (43 characters, `[A-Za-z0-9_-]`). Each side
writes only its own directory; files are written atomically. Each side deletes stale files
(older than 5 minutes) only in the directory it reads.

Request:

```json
{"v":1,"nonce":"…","consumer":"org.kysecurity.mail","clientId":"…",
 "origin":"https://relay.example","issuer":"https://id.example","createdAtMs":1760000000000}
```

- `consumer`: the consumer's bundle ID; must be in KyAuth's `TrustedConsumers`, which maps it to
  a display name and its return scheme (`org.kysecurity.mail` → "KyPost", `kypost`).
- `clientId`: the consumer server's KyIdentity `client_id`, `[A-Za-z0-9._:-]{1,128}`.
- `origin`: the relay URL the user typed, canonicalised as on Android (`https://host[:port]`,
  default port dropped, ≤256 characters). KyAuth refuses a value that is not already canonical.
- `issuer`: the KyIdentity URL from the relay's `/api/auth/sso-config`. KyAuth refuses unless it
  is the paired KyIdentity (same scheme, host, port and path). This replaces Android KyPost's
  account `server_url` check, which iOS cannot read across apps.

Response, exactly one of:

```json
{"v":1,"nonce":"…","status":"ok","idToken":"…"}
{"v":1,"nonce":"…","status":"cancelled"}
{"v":1,"nonce":"…","status":"error","message":"…"}
```

`message` is user-facing text (≤200 characters).

## Flow

1. The consumer reads `/api/auth/sso-config`, writes the request and opens
   `kyauth://signon?nonce=<nonce>`. If the open fails, it tells the user to install KyAuth.
2. KyAuth reads and deletes the request; a missing file, a bad nonce or a request older than
   120 s (or more than 30 s in the future) writes nothing it can address, so it shows
   "Sign-in request expired" and stops. An unknown `consumer` is treated the same way: KyAuth has
   no return scheme for it. It then checks, in order: client ID, origin, pairing (a user ID),
   issuer and `canSignOn`. A failure writes an `error` response.
3. KyAuth shows "<app> at <relay host[:port]> wants to sign in as <user> at <KyIdentity host>."
   with Cancel and Sign In. This works while the vault is locked: no vault key is used.
4. Sign In signs the RFC 7523 assertion with the device key (one Face ID / passcode prompt),
   redeems it at `/oauth/token` and writes `ok` with the ID token. Cancel or a cancelled prompt
   writes `cancelled`. KyIdentity refusals map to the same messages as Android.
5. KyAuth opens `<return scheme>://kyidentity-signon?nonce=<nonce>`.
6. The consumer accepts a response only for the nonce it is waiting for (held in memory,
   abandoned after 180 s), reads and deletes it, and swaps the ID token at the relay's
   `/api/auth/native/signon` for a pairing link exactly as KyPost Android does. It also checks
   for its response when it becomes active, so a user who switches back by hand is not stuck.

The ID token is never logged and lives on disk only between steps 4 and 6, in a container
readable by apps of the same team.
