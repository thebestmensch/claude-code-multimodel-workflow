# Break-glass — when the gate cannot pass and the branch must move

The emergency path is **disabling the ruleset itself** — loud and
audit-logged, never quiet. Deliberately NOT a bypass actor: agents typically
authenticate as the repo owner, so a standing bypass would be silently
walkable by exactly the actors the ruleset constrains. Disabling is two API
calls with a visible window in the audit trail.

Legitimate triggers: an Actions outage, a suite broken by something outside
any PR's diff, a security fix that cannot wait for a wedged gate.

## The runbook

1. Find the ruleset id:
   ```bash
   gh api repos/<owner>/<repo>/rulesets --jq '.[] | {id, name, enforcement}'
   ```
2. Disable:
   ```bash
   gh api -X PUT repos/<owner>/<repo>/rulesets/<ID> -f enforcement=disabled
   ```
3. Do the emergency merge/push. Nothing else while the window is open.
4. Re-enable:
   ```bash
   gh api -X PUT repos/<owner>/<repo>/rulesets/<ID> -f enforcement=active
   ```
5. Post what happened and why on the relevant ticket — including the window's
   start/end. The audit surface differs by account type: orgs have the org
   audit log; a personal account has only Settings → Security log, so the
   ticket note is the durable record.

## What break-glass is NOT

- **Not** a way past a red check on your own PR. Fix the check.
- **Not** editing the ruleset's required-check list to get a merge through.
  That is a policy change; it goes through a PR to the ruleset JSON and a
  deliberate re-apply — never through the UI mid-incident.
- **Not** a standing state. If the ruleset has been disabled for more than
  the incident, the incident is now "the ruleset is disabled."
