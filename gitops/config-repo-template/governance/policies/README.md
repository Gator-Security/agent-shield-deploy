# Policies

One file per policy. A PR touching this directory requires security-team review
(CODEOWNERS) — merging IS the policy-change approval, recorded in git history.

Applied to the cluster by the `config-sync` reconciler (roadmap: G8RV2_CONFIG_SYNC_BRIEF)
through the admin-guarded management APIs, stamped with the commit SHA. Until it ships,
apply reviewed policies via the documented management API calls.
