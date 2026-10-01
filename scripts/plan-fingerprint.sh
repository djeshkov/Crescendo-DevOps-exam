#!/usr/bin/env bash
# Prints a stable SHA-256 of what a saved Terraform plan would change: every resource address,
# its actions and its planned values. Two plans with the same fingerprint make the same changes.
# Used by CI to guarantee that apply executes exactly the plan a human approved.
set -euo pipefail

plan_file=${1:?usage: plan-fingerprint.sh <planfile>}

terraform show -json "${plan_file}" |
  jq -S '[.resource_changes[]?
          | select(.change.actions != ["no-op"])
          | {address, actions: .change.actions, after: .change.after, after_unknown: .change.after_unknown}]' |
  sha256sum | cut -d' ' -f1
