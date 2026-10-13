# Performance Matters blog

Jekyll source for https://travisdowns.github.io. Detailed docs are in `_docs/`
(not published): `_docs/build-and-publish.md` and `_docs/comments.md`. Read the
relevant one before changing the build or the comment system.

## Must know

- **The repository is public.** Never commit secrets, not even in `_docs/` or
  `.claude/`. Files starting with `_` or `.` are left off the website but are
  still readable on GitHub. Root files like `README.md` and `staticman.yml` *are*
  published as raw files.
- **GitHub Pages does not build this site.** The "CI" workflow builds it with
  Jekyll and commits the HTML to `gh-pages:/docs`. If a push to `master` does not
  change the site, check `gh workflow list --all`: the CI workflow gets
  `disabled_inactivity` after ~60 quiet days (fix: `gh workflow enable CI`, then
  push).
- The "External Links" CI job fails routinely (sites returning 401/403 to bots).
  It does not block publishing.

## Building locally

CI uses Ruby 2.7.3 and Jekyll 4.2.0 (`--strict`). On this machine's Ruby 3.3:

```bash
bundle config set --local path vendor/bundle
BUNDLER_VERSION=2.6.7 bundle _2.6.7_ install
RUBYOPT="-r$PWD/_scripts/ruby3-compat.rb" BUNDLER_VERSION=2.6.7 \
  bundle _2.6.7_ exec jekyll build -d /tmp/site
```

Without `BUNDLER_VERSION=2.6.7` Bundler switches to the lockfile's 2.1.4 and
recurses forever; without the compat file Jekyll crashes in `Logger#level` and
Liquid in `String#untaint`.

## Content

- Posts: `_posts/YYYY-MM-DD-slug.md`, `layout: post`, `category: blog`, `tags`.
  Every tag needs `tags/<tag>.md` or the build fails.
- Post assets: `assets/<name>/`, front matter `assets: /assets/<name>`, and
  `{% include post-boilerplate.liquid %}` at the top to get `{{assetpath}}`.
- Theme is the vendored `_minima-fork-v3`; edit it there.

## Comments

- Comments are YAML files in `_data/comments/<slug>/`, delivered as PRs from
  `travisdowns-bot` by comment-worker, a Cloudflare Worker at
  `https://comment-worker.comment-worker.workers.dev` (source:
  github.com/travisdowns/comment-worker, cloned at `~/dev/comment-worker`).
  Spam is flagged with a `[likely spam]` title and a `likely-spam` label.
- Moderate with `gh pr merge <n> --merge --delete-branch` or
  `gh pr close <n> --delete-branch` (always delete the branch).
- The worker reads `staticman.yml` from `master` on every request, so changes to
  it take effect without redeploying the worker.
- Do not change the entry format (`_id`, `_parent`, `replying_to_uid`, epoch
  `date`, MD5 `email`) without updating the templates: reply threading depends
  on `_id`/`replying_to_uid`.
- Testing the deployed worker creates real PRs; close them afterwards. For local
  testing use a mock GitHub API and Cloudflare's Turnstile test keys (see
  `_docs/comments.md`).
