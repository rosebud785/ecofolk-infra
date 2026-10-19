# modules/web_hosting — Firebase Hosting site for the web build

ecofolk-infra#22 (BUILD_PLAN §11.5's frontend half; Architect re-spec 2026-10-09: Firebase Hosting, not
Cloudflare Pages). Manages, on one project, with the `google-beta` provider:

- `google_firebase_project`: adds Firebase to the existing GCP project (`modules/auth` does not declare
  it, so this module is its one home);
- `google_firebase_hosting_site` with `site_id = "<project_id>-web"`.

Outputs: `default_url` (`https://<site>.web.app`), `default_host` (the same without the scheme, the form
`modules/auth`'s `web_host` takes) and `site_id`. In `environments/dev`, `default_host` feeds the auth
config's authorized domains unless `web_host` is set.

Needs `firebase.googleapis.com` and `firebasehosting.googleapis.com`, both enabled by `modules/project`.

## Region

Hosting serves **static web files** (HTML, JS, CSS) from Google's global CDN. There's no region to pin, and
**no user data or compute** runs there. Cloudflare Pages was equally global. The Montréal rule applies to
the API, the database and media, which all stay pinned.

## Not here

- **deploys**: `firebase deploy --only hosting` runs from the local deploy pipeline (ecofolk#408), with
  its own credentials;
- **`firebase.json`** (SPA rewrite to `index.html`, security headers): the private app repo, next to the
  web build;
- **the custom domain** (`google_firebase_hosting_custom_domain`): waits on ecofolk#670 and #23. The
  module's tests fail if one appears.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| google-beta | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| google-beta | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [google-beta_google_firebase_hosting_site.web](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_firebase_hosting_site) | resource |
| [google-beta_google_firebase_project.this](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_firebase_project) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | GCP project id to add Firebase to and host the web build in. The site id is <project_id>-web. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| default_host | Bare hostname of default_url (no scheme), the form modules/auth's web_host takes. |
| default_url | The site's default URL (https://<site>.web.app), for the auth authorized domains and the API's CORS allowlist. |
| site_id | The Hosting site id, for `firebase deploy --only hosting:<site>` (ecofolk#408). |
<!-- END_TF_DOCS -->
