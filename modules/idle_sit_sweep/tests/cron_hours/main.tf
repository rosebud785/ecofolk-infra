# Test helper for idle_sit_sweep.tftest.hcl (#17 amendment AC): expands a cron expression's hour field into
# the list of hours it fires in. Handles n, a-b, a-b/s, */s, * and comma lists; any other part expands to
# [-1], so an assertion on the range fails instead of passing on a shape it can't read.
terraform {
  required_version = ">= 1.5.0"
}

variable "schedule" {
  type        = string
  description = "A 5-field cron expression."
}

locals {
  hour_field = split(" ", var.schedule)[1]

  hours = distinct(flatten([
    for p in split(",", local.hour_field) : (
      can(regex("^[0-9]+$", p)) ? [tonumber(p)] :
      can(regex("^[0-9]+-[0-9]+$", p)) ? range(tonumber(split("-", p)[0]), tonumber(split("-", p)[1]) + 1) :
      can(regex("^[0-9]+-[0-9]+/[0-9]+$", p)) ? range(
        tonumber(split("-", split("/", p)[0])[0]),
        tonumber(split("-", split("/", p)[0])[1]) + 1,
        tonumber(split("/", p)[1])
      ) :
      can(regex("^\\*/[0-9]+$", p)) ? range(0, 24, tonumber(split("/", p)[1])) :
      p == "*" ? range(0, 24) :
      [-1]
    )
  ]))
}

output "hours" {
  value       = local.hours
  description = "The hours (0-23) the schedule fires in; [-1] marks a part this helper can't read."
}
