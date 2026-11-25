#!/usr/bin/env bash
# Builds a short, sanitized Markdown summary from a Terraform plan JSON and a
# Checkov JSON report. Only resource addresses, actions and check IDs are
# printed: never attribute values.
#
# usage: plan-summary.sh <tfplan.json> <checkov.json> <title> <commit-sha>
set -euo pipefail

plan_json="$1"
checkov_json="$2"
title="$3"
sha="${4:0:7}"

changes=$(jq -r '
  [.resource_changes[]?
   | select(.change.actions != ["no-op"] and .change.actions != ["read"])
   | {address,
      action: (if .change.actions == ["create"] then "create"
               elif .change.actions == ["update"] then "update"
               elif .change.actions == ["delete"] then "destroy"
               else "replace" end)}]' "$plan_json")

count() { jq -r --arg a "$1" '[.[] | select(.action == $a)] | length' <<<"$changes"; }
add=$(count create); upd=$(count update); rep=$(count replace); del=$(count destroy)
total=$(jq 'length' <<<"$changes")

# Checkov prints one object for one framework, or a list for several.
results=$(jq -c 'if type == "array" then . else [.] end
  | {passed:  ([.[].summary.passed]  | add // 0),
     failed:  ([.[].summary.failed]  | add // 0),
     skipped: ([.[].summary.skipped] | add // 0),
     fails:   [.[].results.failed_checks[]? | {id: .check_id, resource, name: .check_name}]}' \
  "$checkov_json" 2>/dev/null || echo '{"passed":0,"failed":0,"skipped":0,"fails":[]}')

passed=$(jq -r '.passed' <<<"$results")
failed=$(jq -r '.failed' <<<"$results")
skipped=$(jq -r '.skipped' <<<"$results")

if [ "$failed" -eq 0 ]; then scan="Passed"; else scan="Failed"; fi

cat <<EOF
<!-- tfpipe-plan -->
### Terraform plan: ${title}

| Add | Change | Replace | Destroy | Checkov |
| :-: | :-: | :-: | :-: | :-: |
| ${add} | ${upd} | ${rep} | ${del} | ${scan} (${passed} passed, ${failed} failed, ${skipped} skipped) |

EOF

if [ "$total" -gt 0 ]; then
  echo "<details><summary>${total} resource change(s)</summary>"
  echo
  echo "| Resource | Action |"
  echo "| --- | --- |"
  jq -r '.[] | "| `\(.address)` | \(.action) |"' <<<"$changes"
  echo
  echo "</details>"
  echo
fi

if [ "$failed" -gt 0 ]; then
  echo "#### Failed checks"
  echo
  echo "| Check | Resource | Description |"
  echo "| --- | --- | --- |"
  jq -r '.fails | sort_by(.id)[] | "| \(.id) | `\(.resource)` | \(.name) |"' <<<"$results"
  echo
fi

echo "<sub>Commit ${sha}. Summary only: the full plan is never posted, since saved plans can contain sensitive values.</sub>"
