# Issue #18 AC: with a mock provider (no credentials, no GCP), assert the version, region, private-only
# IP, deletion protection by default, the IAM authentication flag, and that the module declares no
# google_sql_user.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  # The provider checks the self-link shape even under mock_provider, so this must look real.
  # (.tftest.hcl files are outside scripts/check-region-pin.sh's *.tf/*.tfvars scan.)
  private_network = "projects/ecofolk-dev/global/networks/ecofolk"
}

run "is_postgres_16_enterprise_in_the_pinned_region" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.database_version == "POSTGRES_16"
    error_message = "database_version must be POSTGRES_16"
  }

  assert {
    condition     = google_sql_database_instance.postgres.region == "northamerica-northeast1"
    error_message = "instance must be in northamerica-northeast1"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].edition == "ENTERPRISE"
    error_message = "edition must be ENTERPRISE"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].tier == "db-f1-micro"
    error_message = "tier must default to db-f1-micro (C7's allowlist)"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].availability_type == "ZONAL"
    error_message = "HA/REGIONAL is out of scope"
  }
}

run "has_no_public_ip" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "ipv4_enabled must be false: no public IP"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].ip_configuration[0].private_network == var.private_network
    error_message = "private_network must be the network passed in"
  }
}

run "backups_are_enabled" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].backup_configuration[0].enabled == true
    error_message = "automated backups must be enabled"
  }
}

run "deletion_protection_defaults_to_true" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.deletion_protection == true
    error_message = "deletion_protection must default to true"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].deletion_protection_enabled == true
    error_message = "settings.deletion_protection_enabled must follow deletion_protection"
  }
}

run "deletion_protection_follows_the_variable" {
  command = plan

  variables {
    deletion_protection = false
  }

  assert {
    condition     = google_sql_database_instance.postgres.deletion_protection == false && google_sql_database_instance.postgres.settings[0].deletion_protection_enabled == false
    error_message = "both deletion protection settings must come from var.deletion_protection"
  }
}

run "iam_authentication_flag_is_on" {
  command = plan

  assert {
    condition = anytrue([
      for f in google_sql_database_instance.postgres.settings[0].database_flags :
      f.name == "cloudsql.iam_authentication" && f.value == "on"
    ])
    error_message = "database flag cloudsql.iam_authentication must be on"
  }
}

run "declares_no_sql_user_or_password" {
  command = plan

  # A resource that doesn't exist can't be referenced, so read the module's own source instead.
  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"(google_sql_user|random_password)\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare a google_sql_user or random_password resource"
  }
}

run "outputs_and_database" {
  command = apply

  assert {
    condition     = google_sql_database.ecofolk.name == "ecofolk" && output.database_name == "ecofolk"
    error_message = "the module must create one database named ecofolk"
  }

  assert {
    condition     = output.connection_name == google_sql_database_instance.postgres.connection_name
    error_message = "connection_name must be the instance's connection name"
  }

  assert {
    condition     = output.private_ip_address == google_sql_database_instance.postgres.private_ip_address
    error_message = "private_ip_address must be the instance's private IP"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}
