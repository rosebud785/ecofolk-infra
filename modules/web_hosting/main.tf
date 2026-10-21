# main.tf — Firebase Hosting site for the web build (ecofolk-infra#22, Architect re-spec 2026-10-09:
# Firebase Hosting, not Cloudflare Pages; BUILD_PLAN §11.5's frontend half).
#
# What is here: Firebase added to the existing GCP project (google_firebase_project; modules/auth does
# not declare it, so this module is its one home), and one Hosting site, site_id "<project_id>-web".
#
# What is deliberately NOT here (Architect spec on #22):
#   - deploys: `firebase deploy --only hosting` runs from the local deploy pipeline (ecofolk#408);
#   - firebase.json (SPA rewrite, security headers): app repo, next to the web build;
#   - the custom domain (google_firebase_hosting_custom_domain): waits on ecofolk#670 and #23.
#
# Region: Hosting serves static web files from Google's CDN, so there is no region argument on either
# resource. See README.md.
#
# Needs firebase.googleapis.com and firebasehosting.googleapis.com (modules/project); callers order it
# with `depends_on`.
#
# LOCAL FOLLOW-UP (conditional, same route as modules/auth): no role is granted up front. tf-apply has
# roles/editor; if the first apply 403s on firebase.projects.update or firebasehosting.sites.create,
# the narrowest role (roles/firebase.admin, or roles/firebasehosting.admin for the site alone) is added
# locally. The deploy identity for ecofolk#408 needs its own role there; that is not this module's.
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"
}

resource "google_firebase_project" "this" {
  provider = google-beta
  project  = var.project_id
}

resource "google_firebase_hosting_site" "web" {
  provider = google-beta
  project  = google_firebase_project.this.project
  site_id  = "${var.project_id}-web${local.env_suffix}"
}
