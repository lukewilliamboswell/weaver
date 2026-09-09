# Roc nightly updates

This repository checks once daily at 13:22 UTC, about four hours
after the upstream 09:00 UTC build. Late publication can wait until the next day.

`.roc-version` is the compiler pin. `.github/roc-nightly.json` selects this
repository's validation workflows, including their validation-only release paths.
The controller, its tests, and job permissions are maintained in
[roc-automation](https://github.com/lukewilliamboswell/roc-automation).
The caller workflows pin shared code to `3937ff6a0fff8926ca0b8449d2555274cfccff0a`.
Dependabot proposes reviewed updates to Actions/workflow references.

Follow the shared [integration and permissions guide](https://github.com/lukewilliamboswell/roc-automation/blob/3937ff6a0fff8926ca0b8449d2555274cfccff0a/docs/integration.md)
for the PR-creation setting, action allowlists, required checks, and first live
GITHUB_TOKEN run. Keep default token permissions read-only. Automatic merging is
enabled only for the updater's verified, pin-only commits after both configured
validation workflows pass. The updater never approves PRs and receives no
protection bypass.

The `main` ruleset requires pull requests and strict, current-branch results from
all CI and release-validation jobs on Linux, macOS, and Windows. The Release
workflow therefore runs its non-publishing bundle validation on every pull
request. Its publication job remains restricted to an explicit release dispatch.
For bot-created nightly PRs, the controller mirrors successful dispatched jobs to
these required contexts before requesting an immediate squash merge. It does not
enable GitHub's repository-wide queued auto-merge setting.

`automation/roc-nightly` is reserved for the bot's pin-only commits. Put manual
compatibility changes on a separate branch. Candidate failures require diagnosis;
do not weaken tests or mechanically replace baselines to accept a compiler.

The PR configuration check validates the local pin and selected workflow files.
The shared repository owns the controller regression suite. Project tests remain
in this repository and run on the exact candidate commit. Scheduled bot-token
acceptance must be verified after merge; file changes alone cannot prove it.

Use the shared [OpenSSF rollout checklist](https://github.com/lukewilliamboswell/roc-automation/blob/3937ff6a0fff8926ca0b8449d2555274cfccff0a/docs/openssf.md)
to record project-specific evidence. This integration does not establish badge
compliance or change repository settings.
