# The workplace SPA uses a PKCE access token

[← the register](../decisions.md)

Decided 2026-08-27 on `kolonie-docs#506`. The workplace single-page application authenticates to the API with an access token obtained through the hosted federated login's public PKCE flow. It sends that token deliberately on API requests in the `Authorization: Bearer` header. The browser client is public by design: it has no client secret.

This record settles the boundary before the workplace requests real work-item data. The consuming implementation work belongs in [`kolonie-workplace`](https://github.com/Kolonie-AI/kolonie-workplace) and [`kolonie-platform`](https://github.com/Kolonie-AI/kolonie-platform); this repository records the choice and its constraints.

## Why the access token

The access token keeps authentication explicit at the request boundary. It is not ambient browser authority, and the API can validate the credential without maintaining a second browser session. The public PKCE flow protects the authorization-code exchange without placing a secret in a browser bundle. The API must validate the token's signature, issuer and audience against the configured tenant and the configured audience for the workplace API. Those deployment values are configuration, not documentation: this record intentionally contains none of them.

After validation, the API resolves the human using the existing `(provider, subject)` pair. It does not create a second notion of a human for the SPA, and it does not use a client identifier as the human identity. This keeps the API aligned with [*A human account is a login, not a membership*](a-human-account-is-a-login.md) and [*One identity table, several ways in, and no password*](one-identity-table-no-password.md).

## The rejected alternatives

### A workplace-scoped session cookie

A cookie would make the API mint and carry a second kind of human session. Because the SPA is a separate origin, that choice also brings cross-site cookie semantics and CSRF protection into an API that does not need them when it validates a bearer credential. It buys nothing the access token does, while adding ambient authority and state to the service that should not acquire a casual browser session.

The console's cookie-backed authentication **does not change**. This decision is for the workplace SPA-to-API boundary only; it neither replaces nor widens the console session mechanism.

### A backend-for-frontend

A backend-for-frontend would turn the workplace deployment from a static, secret-free client into a server that holds a credential or exchanges one on the client's behalf. That reverses the deployment shape already chosen for the workplace and adds a permanent operational surface merely to avoid implementing JWT validation in the API. The cost is larger than the problem: the API must validate a token in either design, and the access-token design avoids another server, secret and failure boundary.

## API and browser contract

The platform implementation must provide the following contract:

- Validate the JWT signature and reject a token whose issuer or audience does not match the configured tenant and workplace API audience.
- Resolve the authenticated human from the existing `(provider, subject)` identity; do not add a SPA-specific human record or identity key.
- Permit cross-origin requests only from the exact workplace origin. The CORS allow-list must not use a wildcard and must not add the console origin by reflex.
- Return `401 Unauthorized` when the credential is absent, expired or invalid.
- Have the workplace return the human to sign-in after `401`; it must not render an empty board that could be mistaken for “no work”.
- Keep the access token out of `localStorage` where the SPA can avoid it. The implementation should use an in-memory or equivalent non-persistent browser representation and attach the value only for the request that needs it.

The CORS rule is deliberately exact rather than a list of deployment names in this record. The configured workplace origin is supplied at deployment time and must be the sole allowed origin for this API path.

## What this does not decide

This record does not implement token validation, CORS, an endpoint, a work-item schema, or an API client-generation strategy. It does not change console authentication. It does not put a tenant value, client identifier, audience string, secret or other deployment credential in documentation.

## What would reopen this

- The API cannot validate issuer, audience and signature without introducing a second human identity or a server-held browser session.
- The workplace requires ambient cookie authority or persistent browser storage to operate securely.
- The exact-origin CORS boundary cannot be enforced for the workplace API without permitting a wildcard or an unrelated origin.
