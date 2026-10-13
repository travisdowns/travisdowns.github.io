# Blog internals

Notes on how the *Performance Matters* blog is built, published and run.

This directory starts with `_`, so Jekyll does not publish it to the site. It is
still part of this **public** repository, so never put secrets here (or anywhere
else in the repo, including git history).

- [build-and-publish.md](build-and-publish.md): how source on `master` becomes the
  site, the CI jobs, branch conventions, local builds and what gets published.
- [comments.md](comments.md): the comment system (form, comment-worker on
  Cloudflare, Turnstile spam flagging, moderation via PRs), its credentials and
  how to operate it.
