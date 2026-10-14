# Issue #22 AC (Architect re-spec 2026-10-09, Firebase Hosting): with a mock provider (no credentials, no
# GCP), assert the Hosting site exists on the project with site_id <project_id>-web, Firebase is added to
# that project, there is no custom-domain resource (and no IAM), and default_url is formatted as a URL.
mock_provider "google-beta" {}

variables {
  project_id = "ecofolk-dev"
}

run "firebase_is_added_to_the_given_project" {
  command = plan

  assert {
    condition     = google_firebase_project.this.project == "ecofolk-dev"
    error_message = "google_firebase_project must be on var.project_id"
  }
}

run "site_exists_with_the_spec_site_id" {
  command = plan

  assert {
    condition     = google_firebase_hosting_site.web.site_id == "ecofolk-dev-web"
    error_message = "site_id must be <project_id>-web"
  }

  assert {
    condition     = google_firebase_hosting_site.web.project == "ecofolk-dev"
    error_message = "the site must be on var.project_id"
  }
}

run "module_declares_no_custom_domain_and_no_iam" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google_[a-z_]*(custom_domain|_iam_[a-z_]*)\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must declare no custom-domain resource (waits on ecofolk#670, #23) and no *_iam_* resource"
  }

  # Guard the guard: the scan above must actually see the module's files.
  assert {
    condition     = contains(fileset(path.module, "*.tf"), "main.tf")
    error_message = "the custom-domain scan found no main.tf, so it proves nothing"
  }
}

run "outputs_are_the_web_app_url" {
  command = plan

  assert {
    condition     = can(regex("^https://[a-z0-9-]+\\.web\\.app$", output.default_url))
    error_message = "default_url must be formatted as https://<site>.web.app"
  }

  assert {
    condition     = output.default_url == "https://ecofolk-dev-web.web.app"
    error_message = "default_url must be https://<project_id>-web.web.app"
  }

  assert {
    condition     = output.default_host == "ecofolk-dev-web.web.app"
    error_message = "default_host must be the bare hostname of default_url"
  }

  assert {
    condition     = output.site_id == "ecofolk-dev-web"
    error_message = "site_id output must echo the site's id"
  }
}

run "rejects_a_malformed_project_id" {
  command = plan

  variables {
    project_id = "EcoFolk_Dev"
  }

  expect_failures = [var.project_id]
}
