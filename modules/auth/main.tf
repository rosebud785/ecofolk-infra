# main.tf — Firebase Auth (Identity Platform) config for one project (ecofolk-infra#20, BUILD_PLAN §11.4).
#
# What is here: the project's google_identity_platform_config, with email + password sign-in ENABLED
# (the shipped identity model, Architect correction on #20), anonymous sign-in left off, anonymous users
# auto-deleted, and the authorized domains from a variable.
#
# What is deliberately NOT here (Architect spec on #20):
#   - no IdP config resource of any kind (google_identity_platform_default_supported_idp_config,
#     *_oauth_idp_config, *_inbound_saml_config): each OAuth provider needs a client secret, and a
#     secret in Terraform ends up in state and inputs. Providers are local follow-up L-AUTH; see README;
#   - no custom auth domain (waits on the domain decision, ecofolk#404/#670);
#   - email-enumeration protection: not in this resource's schema, set out of band (README).
#
# Needs identitytoolkit.googleapis.com (modules/project); callers order it with `depends_on`.
#
# LOCAL FOLLOW-UP (conditional, same route as modules/cloudsql): no role is granted up front. tf-apply
# has roles/editor, which is expected to cover identitytoolkit.config.*; the first apply is the
# measurement. If it returns a 403, the narrowest role (roles/identitytoolkit.admin on the project) is
# added locally.
resource "google_identity_platform_config" "auth" {
  project = var.project_id

  authorized_domains = local.authorized_domains

  autodelete_anonymous_users = true

  sign_in {
    email {
      enabled           = true
      password_required = true
    }
    # No `anonymous` block: anonymous sign-in stays off.
  }
}

locals {
  # Spec default: localhost plus the dev web host. compact() drops web_host while it is unset.
  authorized_domains = var.authorized_domains != null ? var.authorized_domains : compact(["localhost", var.web_host])
}
