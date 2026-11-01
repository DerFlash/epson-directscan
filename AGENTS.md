# Repository maintenance

- Merge work through a pull request after the relevant checks pass.
- Merged branches are cleaned automatically by the `Cleanup merged branches`
  GitHub Actions workflow. It also checks recent closed PRs after pushes to
  `main`, so cleanup does not depend on a browser or a locally authenticated CLI.
- Before finishing, inspect that workflow's result and read back the remote
  branches through the GitHub connector. Do not open a browser for branch cleanup.
- The default branch, protected branches, branches used by open PRs, forks and
  branches with commits added after their merge must be preserved.
- Never bypass the expected-commit lease or force-delete a preserved branch.
  If cleanup fails, inspect the workflow logs and report the concrete blocker.
