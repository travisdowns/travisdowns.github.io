# Build and publish

## Overview

```
master (Jekyll source)
  │  push, or nightly schedule (01:42 UTC)
  ▼
GitHub Actions "CI" (.github/workflows/ci.yml)
  │  build-site action: Ruby 2.7.3, Jekyll 4.2.0, `jekyll build --strict`
  │  _scripts/publish-github.sh commits the rendered HTML
  ▼
gh-pages branch, docs/ directory
  │  GitHub Pages ("legacy" build type, source gh-pages /docs)
  ▼
https://travisdowns.github.io
```

GitHub Pages does **not** run Jekyll itself (`.nojekyll` is included in the
output). Everything is built in CI, so the site only changes when the CI
workflow runs and publishes.

## CI workflows

`.github/workflows/ci.yml` (name "CI"), on every push and nightly:

| Job | What it does |
|---|---|
| Build and Publish | Builds with `_scripts/build-site.sh`, publishes to the branch chosen by `_scripts/ci-vars.sh`, uploads `_site` as an artifact |
| Take Screenshots | Light/dark at 414px and 1200px, pushed to [travisdowns/blog-screenshots](https://github.com/travisdowns/blog-screenshots) (needs the `SNAPSHOT_REPO_AUTH` secret). Skipped for comment branches (`staticman_*`, `commentworker_*`) |
| Internal Links, External Links, Check HTML, Miscellaneous | Scripts in `_scripts/checks/`, mostly html-proofer |

**External Links fails routinely** because some sites (unsplash.com,
cppreference.com) reject bots with 401/403. It does not block publishing: the
build/publish job is separate and runs first.

`.github/workflows/lighthouse.yml` runs Lighthouse CI on pushes to `master` and
`lhci`.

### Publish branch mapping

`_scripts/ci-vars.sh` decides where a push publishes:

- `master` publishes to `gh-pages` (the live site)
- `publish-artifact` publishes to `gh-test`
- any other branch `X` publishes to `X-site` **if that branch exists** (for
  example `dark-mode` and `dark-mode-site`), otherwise it builds but does not
  publish

Per-branch environment variables can go in `_scripts/props/<branch-slug>`.
Pushes from the `blog-test` repository add `_config-test.yml` (sets
`baseurl: /blog-test`).

### Gotcha: CI disabled for inactivity

GitHub disables workflows that have a `schedule` trigger after about 60 days
without repository activity. The state shows as `disabled_inactivity` and then
**nothing publishes, even on push**. This happened between August and October
2026. Check and fix with:

```bash
gh workflow list --all          # look for "CI ... disabled_inactivity"
gh workflow enable CI
```

The workflow has no `workflow_dispatch` trigger, so after enabling it a push to
`master` is needed to rebuild.

## What gets published

Jekyll skips files and directories whose names start with `_` or `.` (other than
its own `_posts`, `_data`, `_includes`, `_layouts`, `_sass`, `_plugins`), plus
`Gemfile`, `vendor/` and similar defaults. Everything else at the top level is
copied or rendered into the site. Notably `README.md` and `staticman.yml` are
served as raw files at `/README.md` and `/staticman.yml`.

Remember that the repository itself is public, so "not published" only means
"not on the website".

## Content conventions

- Posts live in `_posts/YYYY-MM-DD-slug.md` with `layout: post`,
  `category: blog` and `tags: [...]`. URLs are
  `/:categories/:year/:month/:day/:title.html`.
- Every tag needs a `tags/<tag>.md` file (front matter `tag-name: <tag>`);
  `_plugins/tag-updater.rb` fails the build if one is missing.
- Post assets go under `assets/<name>/` and are referenced by setting
  `assets: /assets/<name>` in the front matter and including
  `{% include post-boilerplate.liquid %}` at the top of the post, which defines
  `assetpath` (and `tablepath` for `misc/tables/<slug>`). Figures use the
  `svg-fig.html`, `carousel-svg-fig-2.html` and `assetimg.md` includes.
- Comments are on by default for posts (`_config.yml` defaults); a page can set
  `comments: true` (non-posts) or `lock_comments: true` (shows existing comments,
  hides the form). The comment system itself is documented privately in
  `~/kb/Notes/Blog-comments-setup.md`.
- `misc/` holds test and debug pages (`misc/comments-test.md`,
  `misc/debug*.md`) and result tables.
- The theme is a vendored minima fork in `_minima-fork-v3`, and
  `jekyll-seo-tag` comes from a patched fork (see `Gemfile`).

## Building locally

CI pins Ruby 2.7.3 with Bundler 2.1.4. On a modern Ruby (3.3) that stack needs
two workarounds: a newer Bundler (2.1.4 recurses forever on Ruby 3.3) and
`_scripts/ruby3-compat.rb` (patches for the old Jekyll and Liquid gems).

```bash
bundle config set --local path vendor/bundle      # once; vendor/ is gitignored
BUNDLER_VERSION=2.6.7 bundle _2.6.7_ install

RUBYOPT="-r$PWD/_scripts/ruby3-compat.rb" BUNDLER_VERSION=2.6.7 \
  bundle _2.6.7_ exec jekyll build -d /tmp/site
# or `jekyll serve` to preview on http://127.0.0.1:4000
```

To point a local build somewhere else (for example a local comment-worker), pass
an extra config file: `--config _config.yml,/path/to/override.yml`.

`_scripts/diff-site.sh` diffs two built sites, which is handy for checking that
a template change did not alter the output.
