# Test files that exercise the failure mode of the bug being fixed.
#
# /capture-eval moves the failing-then-passing test(s) here so the case is
# self-contained: a fresh runner can run hidden-tests/ to verify the bug
# reproduces on `beforeCommit` and the fix works on `afterCommit`.
#
# These tests are NOT committed in the dotfiles repo; the golden case just
# documents where they live in the source repo and the runner fetches them via
# git checkout.
