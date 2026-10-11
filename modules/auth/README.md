# modules/auth — Firebase Auth (Identity Platform) config

ecofolk-infra#20 (BUILD_PLAN §11.4). Manages one project's `google_identity_platform_config`:

- **email + password sign-in enabled** (`password_required = true`): the shipped identity model, and the
  only kind the web app uses today (`signInWithEmailAndPassword`, `sendPasswordResetEmail`);
- **no anonymous sign-in**, and `autodelete_anonymous_users = true`;
- `authorized_domains` from a variable; the default is `localhost` plus `var.web_host`.

Output `auth_domain` is `<project>.firebaseapp.com`, for the web build's Firebase config.

Wired into `environments/dev` only. Prod gets it through C12 (#12) at go-live.

## Sign-in providers

OAuth providers are added **alongside** email/password, never instead of it. Each needs a client
secret, and a secret in Terraform ends up in state and inputs, so **no IdP config resource lives in
this repo**. The module's tests fail if one appears.

| Provider | Where the secret lives | Who wires it | Status |
| --- | --- | --- | --- |
| Email / password | no secret | this module | **on** (dev) |
| Google | Secret Manager (OAuth client created in the console) | local session, L-AUTH: IdP config applied from a `local-only/` path or by hand | waiting on L-AUTH |
| Apple | Secret Manager, once the account exists | local session, L-AUTH | waiting on the Apple developer account |
| Facebook | Secret Manager, once the account exists | local session, L-AUTH | waiting on the Facebook developer account |

## Set out of band

- **Email-enumeration protection** (`emailPrivacyConfig.enableImprovedEmailPrivacy`) is not in
  `google_identity_platform_config`'s schema (checked in provider 5.45.2, this repo's lock, and 6.50.0),
  so it is set out of band under ecofolk#786, right after this module's first dev apply.

## Not here

- the custom auth domain (waits on the domain decision, ecofolk#404/#670);
- mapping Firebase UIDs to app users (app code, private repo).
