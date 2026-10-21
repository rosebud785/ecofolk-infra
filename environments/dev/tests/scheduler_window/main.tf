# Test helper for scheduler_window.tftest.hcl (#99): lists every Cloud Scheduler job that breaks the dev
# invariant, America/Chicago and no run while #14 has dev Cloud SQL stopped. The stop job itself fires at
# 22:15 and the start job at 04:45, so the window is open at both ends: a run is inside it when it is after
# 22:15 or before 04:45 CT. Day-of-month, month and day-of-week are ignored: a run inside the window on any
# day is a violation.
#
# The minute and hour fields are expanded like modules/idle_sit_sweep/tests/cron_hours: n, a-b, a-b/s,
# n/s, */s, * and comma lists. Any other part (names, ?, L, ...) expands to [-1], which is reported as
# unreadable, so a shape the helper can't read fails instead of passing.
terraform {
  required_version = ">= 1.5.0"
}

variable "jobs" {
  type = list(object({
    name      = string
    schedule  = string
    time_zone = string
  }))
  description = "Every Cloud Scheduler job in the composition (environments/dev's scheduler_jobs output)."
}

locals {
  time_zone = "America/Chicago"
  stop_at   = 22 * 60 + 15 # minutes after midnight CT, modules/sql_off_hours' stop
  start_at  = 4 * 60 + 45  # modules/sql_off_hours' start

  parsed = [for j in var.jobs : {
    name      = j.name
    schedule  = coalesce(j.schedule, "")
    time_zone = j.time_zone
    fields    = split(" ", coalesce(j.schedule, ""))
  }]

  expanded = [for j in local.parsed : merge(j, {
    minutes = length(j.fields) != 5 ? [-1] : distinct(flatten([
      for p in split(",", j.fields[0]) : (
        can(regex("^[0-9]+$", p)) ? [tonumber(p)] :
        can(regex("^[0-9]+-[0-9]+$", p)) ? range(tonumber(split("-", p)[0]), tonumber(split("-", p)[1]) + 1) :
        can(regex("^[0-9]+-[0-9]+/[0-9]+$", p)) ? range(
          tonumber(split("-", split("/", p)[0])[0]),
          tonumber(split("-", split("/", p)[0])[1]) + 1,
          tonumber(split("/", p)[1])
        ) :
        can(regex("^[0-9]+/[0-9]+$", p)) ? range(tonumber(split("/", p)[0]), 60, tonumber(split("/", p)[1])) :
        can(regex("^\\*/[0-9]+$", p)) ? range(0, 60, tonumber(split("/", p)[1])) :
        p == "*" ? range(0, 60) :
        [-1]
      )
    ]))
    hours = length(j.fields) != 5 ? [-1] : distinct(flatten([
      for p in split(",", j.fields[1]) : (
        can(regex("^[0-9]+$", p)) ? [tonumber(p)] :
        can(regex("^[0-9]+-[0-9]+$", p)) ? range(tonumber(split("-", p)[0]), tonumber(split("-", p)[1]) + 1) :
        can(regex("^[0-9]+-[0-9]+/[0-9]+$", p)) ? range(
          tonumber(split("-", split("/", p)[0])[0]),
          tonumber(split("-", split("/", p)[0])[1]) + 1,
          tonumber(split("/", p)[1])
        ) :
        can(regex("^[0-9]+/[0-9]+$", p)) ? range(tonumber(split("/", p)[0]), 24, tonumber(split("/", p)[1])) :
        can(regex("^\\*/[0-9]+$", p)) ? range(0, 24, tonumber(split("/", p)[1])) :
        p == "*" ? range(0, 24) :
        [-1]
      )
    ]))
  })]

  checked = [for j in local.expanded : merge(j, {
    readable = !contains(j.minutes, -1) && !contains(j.hours, -1)
    inside = sort([for r in [for hm in setproduct(j.hours, j.minutes) : hm[0] * 60 + hm[1]] :
      format("%02d:%02d", floor(r / 60), r % 60) if r > local.stop_at || r < local.start_at
    ])
  })]

  violations = flatten([for j in local.checked : concat(
    j.time_zone == local.time_zone ? [] : ["${j.name}: time_zone is ${coalesce(j.time_zone, "unset")}, not ${local.time_zone}"],
    j.readable ? [] : ["${j.name}: can't read the minute or hour field of \"${j.schedule}\""],
    j.readable && length(j.inside) > 0 ? ["${j.name}: \"${j.schedule}\" fires at ${j.inside[0]} CT, inside dev's 22:15–04:45 CT Cloud SQL stop"] : [],
  )])
}

output "violations" {
  value       = local.violations
  description = "One line per broken rule per job; empty when every job is America/Chicago and outside the stop window."
}

output "job_count" {
  value       = length(var.jobs)
  description = "How many jobs were checked, so an empty list can't pass as \"no violations\"."
}
