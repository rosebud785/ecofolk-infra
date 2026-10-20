output "topic_id" {
  value       = google_pubsub_topic.budget.id
  description = "The budget topic (projects/<project>/topics/<name>), for the local budget wiring (ef#885)."
}

output "function_name" {
  value       = google_cloudfunctions2_function.killswitch.name
  description = "The kill-switch function's name, for the local run.invoker grant on its service (ef#885)."
}

output "service_account_email" {
  value       = local.service_account_email
  description = "The runtime and trigger SA the function expects (created locally, ef#885)."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value = concat(
    [for s in google_project_service.apis : "google_project_service/${s.service}"],
    [
      "google_pubsub_topic/${google_pubsub_topic.budget.name}",
      "google_storage_bucket/${google_storage_bucket.source.name}",
      "google_cloudfunctions2_function/${google_cloudfunctions2_function.killswitch.name}",
    ],
  )
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
