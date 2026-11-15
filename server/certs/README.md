Put credentials here locally (this directory is git-ignored except for this file).

- `AppleRootCA-G3.cer`: download from https://www.apple.com/certificateauthority/ ("Apple Root CA - G3 Root").
  Point `APPLE_ROOT_CA_PATH` at it. Verify the SHA-256 fingerprint shown on that page:
  `openssl x509 -inform der -in AppleRootCA-G3.cer -noout -fingerprint -sha256`
  and set the same value in `APPLE_ROOT_CA_SHA256` so a swapped file is refused at startup.
- `AuthKey_XXXXXXXXXX.p8`: the APNs auth key. Point `APNS_KEY_PATH` at it.
