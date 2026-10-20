# Issue #20 AC (with the 2026-10-11 Architect correction): with a mock provider (no credentials, no GCP),
# assert the config exists, email sign-in is ENABLED with password_required = true, anonymous sign-in is
# off and anonymous users are auto-deleted, and no *_idp_config resource appears in the module.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  web_host   = "dev.ecofolk.example"
}

run "config_exists_on_the_given_project" {
  command = plan

  assert {
    condition     = google_identity_platform_config.auth.project == "ecofolk-dev"
    error_message = "the identity platform config must be on var.project_id"
  }
}

run "email_sign_in_is_enabled_with_a_password" {
  command = plan

  assert {
    condition     = google_identity_platform_config.auth.sign_in[0].email[0].enabled == true
    error_message = "email sign-in must be ENABLED (Architect correction on #20: email + password is the identity model)"
  }

  assert {
    condition     = google_identity_platform_config.auth.sign_in[0].email[0].password_required == true
    error_message = "email sign-in must require a password"
  }
}

run "anonymous_is_off_and_anonymous_users_are_deleted" {
  command = plan

  assert {
    condition     = length(google_identity_platform_config.auth.sign_in[0].anonymous) == 0
    error_message = "there must be no anonymous sign-in block"
  }

  assert {
    condition     = google_identity_platform_config.auth.autodelete_anonymous_users == true
    error_message = "autodelete_anonymous_users must be true"
  }
}

run "module_declares_no_idp_config" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google_[a-z_]*(idp_config|saml_config)\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must declare no *_idp_config resource: OAuth client secrets never go into Terraform (L-AUTH)"
  }

  # Guard the guard: the scan above must actually see the module's files.
  assert {
    condition     = contains(fileset(path.module, "*.tf"), "main.tf")
    error_message = "the idp_config scan found no main.tf, so it proves nothing"
  }
}

run "authorized_domains_default_to_localhost_and_the_web_host" {
  command = plan

  assert {
    condition     = google_identity_platform_config.auth.authorized_domains == tolist(["localhost", "dev.ecofolk.example"])
    error_message = "authorized_domains must default to localhost plus var.web_host"
  }
}

run "authorized_domains_without_a_web_host_is_localhost" {
  command = plan

  variables {
    web_host = null
  }

  assert {
    condition     = google_identity_platform_config.auth.authorized_domains == tolist(["localhost"])
    error_message = "with no web_host, authorized_domains must be just localhost"
  }
}

run "authorized_domains_follow_the_variable" {
  command = plan

  variables {
    authorized_domains = ["localhost", "ecofolk-dev.firebaseapp.com"]
  }

  assert {
    condition     = google_identity_platform_config.auth.authorized_domains == tolist(["localhost", "ecofolk-dev.firebaseapp.com"])
    error_message = "authorized_domains must come from var.authorized_domains when set"
  }
}

run "outputs_the_auth_domain" {
  command = plan

  assert {
    condition     = output.auth_domain == "ecofolk-dev.firebaseapp.com"
    error_message = "auth_domain must be <project>.firebaseapp.com"
  }
}

run "rejects_a_web_host_with_a_scheme" {
  command = plan

  variables {
    web_host = "https://dev.ecofolk.example"
  }

  expect_failures = [var.web_host]
}

run "rejects_an_authorized_domain_with_a_path" {
  command = plan

  variables {
    authorized_domains = ["localhost", "dev.ecofolk.example/app"]
  }

  expect_failures = [var.authorized_domains]
}

# Issue #13: the config is one per project, so resource_names lists it under the project's name, and
# environments/qa's collision test catches a qa root that calls this module on dev's project.
run "resource_names_lists_the_config" {
  command = plan

  assert {
    condition     = output.resource_names == ["google_identity_platform_config/ecofolk-dev"]
    error_message = "resource_names must be the project's one config (#13), got ${jsonencode(output.resource_names)}"
  }
}
