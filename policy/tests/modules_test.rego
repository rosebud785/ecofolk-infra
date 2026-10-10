package main

test_module_local_dot_pass if {
	count(deny) == 0 with input as tfmod("environments/dev/main.tf", {"source": "./net"})
}

test_module_local_parent_pass if {
	count(deny) == 0 with input as tfmod("environments/dev/main.tf", {"source": "../../modules/project", "project_id": "ecofolk-dev"})
}

test_module_registry_fail if {
	msgs := deny with input as tfmod("environments/dev/main.tf", {"source": "terraform-google-modules/iam/google//modules/projects_iam", "version": "8.0.0"})
	denied_with(msgs, "source must be a local path (./ or ../)")
}

test_module_git_fail if {
	msgs := deny with input as tfmod("environments/dev/main.tf", {"source": "git::https://github.com/example/tf-modules.git//iam?ref=v1"})
	denied_with(msgs, "source must be a local path (./ or ../)")
}

test_module_github_shorthand_fail if {
	msgs := deny with input as tfmod("modules/project/main.tf", {"source": "github.com/example/tf-modules//run"})
	denied_with(msgs, "source must be a local path (./ or ../)")
}

test_module_https_archive_fail if {
	msgs := deny with input as tfmod("environments/prod/main.tf", {"source": "https://example.com/run.zip"})
	denied_with(msgs, "source must be a local path (./ or ../)")
}

# A bare directory name is a registry address to Terraform, not a local path.
test_module_bare_name_fail if {
	msgs := deny with input as tfmod("environments/dev/main.tf", {"source": "modules/project"})
	denied_with(msgs, "source must be a local path (./ or ../)")
}

test_module_source_unset_fail if {
	msgs := deny with input as tfmod("environments/dev/main.tf", {"project_id": "ecofolk-dev"})
	denied_with(msgs, "source must be a local path (./ or ../), got <unset>")
}

# local-only/ exempts IAM resources, not remote modules.
test_module_remote_in_local_only_fail if {
	msgs := deny with input as tfmod("local-only/iam.tf", {"source": "terraform-google-modules/iam/google"})
	denied_with(msgs, "source must be a local path (./ or ../)")
}
