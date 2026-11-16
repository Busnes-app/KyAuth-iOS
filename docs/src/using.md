# Everyday tasks

## TOTP accounts

Use the Codes tab to add an account from its setup QR/link or secret, then verify a code with the service. Unlocking the vault requires Face ID or the device passcode. The app locks immediately in the background and also after the configured idle period.

## Push approvals

Approve only a sign-in you initiated. Enter the two digits displayed by that browser and authenticate on the phone. Push approvals can work while the TOTP vault is locked; they use the device key separately.

## Suite sign-on

Supported iOS suite apps request sign-on through KyAuth's shared App Group handoff. Finish the current request before starting another. This integration requires matching application capabilities; installing two arbitrary source builds does not establish it.

## Protect access

Optional app PIN protection has a delay ladder and erases local data after five failed attempts. Before replacing or erasing the phone, establish another way into all enrolled accounts.

## TOTP setup keys

Setup keys need at least 10 decoded bytes (80 bits). An issuer-provided key between 80 and 127 bits is accepted with a short-key warning. A retained account below 80 bits is unavailable for code generation; use the issuing service to replace its secret. Preserve its record until recovery is verified.
