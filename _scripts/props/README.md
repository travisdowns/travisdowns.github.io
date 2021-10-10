This props file contains environment variables that are loaded in CI
by the ci-vars.sh script, based on the branch name. The `default` properties
are always loaded from `props/default`, then `props/$BRANCH` is loaded
(overriding defaults) if it exists.

This lets you have branch-specific variables and behavior without a bunch
of messy if cascades in your CI.
