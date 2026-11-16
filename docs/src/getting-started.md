# Getting started

## Prepare the device

Set an iPhone or iPad passcode before using KyAuth. Source installation requires a Mac, Xcode and appropriate Apple signing and capabilities. A simulator is useful for development, but does not establish that APNs, App Attest or Secure Enclave signing work on a phone.

## Pair and verify

Use a fresh device-pairing code from your KyIdentity server. Complete the app's pairing flow against the intended HTTPS server and allow notifications for push approvals. Keep another sign-in/recovery method until a real sign-in has succeeded.

TOTP secrets have no backup, export or sync. Save the recovery codes issued by every service before relying on this device.
