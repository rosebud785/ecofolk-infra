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
