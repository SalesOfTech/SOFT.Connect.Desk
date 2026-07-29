# Operator OAuth

`SOFT.Connect.Desk Operator` uses SOFT.Connect as a public OAuth 2.0 / OpenID
Connect client. The Support build does not compile or use this integration.

## Flow

- Authorization Code Flow with PKCE S256.
- The system browser is used; an embedded WebView is not used.
- The callback listener binds only to `127.0.0.1` on an OS-selected dynamic
  port and accepts `/oauth/callback`.
- `state` and ID-token `nonce` are checked against 32-byte random Base64URL
  values.
- Access and ID tokens must use RS256 and pass JWKS signature, issuer,
  audience, time, active-account and Operator-permission checks.
- `/oauth/me` is checked before a session is accepted.

## Session storage

Tokens are stored as separate native credentials:

- Windows Credential Manager;
- macOS Keychain;
- Linux Secret Service.

The rotated refresh token is replaced before the other session entries are
updated. Access and ID tokens are never written to the normal application
configuration or logs.

## Release readiness

Do not publish an Operator release until the SOFT.Connect production migration,
signing key generation and service restart are complete. The production smoke
test must cover:

1. successful employee sign-in;
2. denial without `soft_connect_desk_operator`;
3. refresh-token rotation;
4. logout and token revocation;
5. relaunch with a stored session on Windows, macOS and Linux.
