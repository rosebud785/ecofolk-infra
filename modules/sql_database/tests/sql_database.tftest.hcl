# Issue #13 AC: with a mock provider (no credentials, no GCP), assert the qa database's name and instance,
# the user name output, that env refuses dev and prod (modules/cloudsql owns their "ecofolk"), and that the
# module declares no instance, no user and no IAM.
mock_provider "google" {}

variables {
  project_id    = "ecofolk-dev"
  instance_name = "ecofolk-pg"
  env           = "qa"
}

run "qa_database_on_the_existing_instance" {
  command = plan

  assert {
    condition     = google_sql_database.this.name == "ecofolk_qa"
    error_message = "the qa database must be ecofolk_qa"
  }

  assert {
    condition     = google_sql_database.this.instance == "ecofolk-pg" && google_sql_database.this.project == "ecofolk-dev"
    error_message = "the database must go on var.instance_name in var.project_id"
  }

  assert {
    condition     = output.database_name == "ecofolk_qa" && output.user_name == "ecofolk_qa_app"
    error_message = "outputs must name the ecofolk_qa database and the ecofolk_qa_app user"
  }

  assert {
    condition     = output.resource_names == ["google_sql_database/ecofolk_qa"]
    error_message = "resource_names must list the one database, got ${jsonencode(output.resource_names)}"
  }
}

run "no_instance_user_or_iam_in_the_module" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") : !can(regex(
        "resource \"(google_sql_database_instance|google_sql_user|random_password|google_[a-z0-9_]*_iam_[a-z0-9_]*)\"",
        file("${path.module}/${f}")
      ))
    ])
    error_message = "modules/sql_database must declare no instance, no user, no password and no IAM (#13)"
  }
}

run "env_refuses_dev" {
  command = plan

  variables {
    env = "dev"
  }

  expect_failures = [var.env]
}

run "env_refuses_prod" {
  command = plan

  variables {
    env = "prod"
  }

  expect_failures = [var.env]
}

run "instance_name_refuses_a_bad_name" {
  command = plan

  variables {
    instance_name = "Not_A_Name"
  }

  expect_failures = [var.instance_name]
}
