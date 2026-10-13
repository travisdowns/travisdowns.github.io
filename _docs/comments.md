# Comments

Comments are static: each one is a YAML file in `_data/comments/<slug>/`,
rendered into the page at build time. New comments arrive as pull requests that
are merged (published) or closed (rejected).

## How it fits together

```
Reader's browser on travisdowns.github.io
  │  1. On Submit, an invisible Cloudflare Turnstile challenge runs and yields a token
  │  2. POST form fields + token (application/x-www-form-urlencoded)
  ▼
comment-worker (Cloudflare Worker)
  │  https://comment-worker.comment-worker.workers.dev/api/handle/form
  │  3. Verifies the Turnstile token with Cloudflare (TURNSTILE_SECRET_KEY)
  │  4. Reads staticman.yml from master, validates fields, builds the YAML entry
  │  5. As travisdowns-bot (GITHUB_TOKEN): creates branch commentworker_<uuid>,
  │     commits _data/comments/<slug>/entry<ms>.yml, opens a PR
  │     (suspected spam: "[likely spam]" title prefix + likely-spam label)
  ▼
GitHub PR on travisdowns/travisdowns.github.io
  │  6. Merge to publish, close to reject
  ▼
CI rebuilds the site (see build-and-publish.md) and the comment appears
```

## Pieces in this repo

| File | Role |
|---|---|
| `_config.yml` | `staticman_url` (the worker endpoint) and `turnstile.siteKey` |
| `staticman.yml` | Entry format, read by the worker **from `master` on every request**: allowed/required fields, `path`, `filename`, `generatedFields.date` (epoch seconds), `transforms` (email is MD5 hashed), `moderation: true` |
| `_includes/comment_form.html` | The form, honeypot field `fields[hp]`, Turnstile container and the privacy note |
| `_includes/comments.html` | Renders top-level comments; loads `assets/main.js` and the Turnstile script |
| `_includes/comment.html` | One comment plus its replies (threaded by `replying_to_uid` matching a parent's `_id`) |
| `assets/main.js` | Submit handler: runs Turnstile, POSTs, shows the result modal; reply-form moving |
| `_data/comments/<slug>/entry<ms>.yml` | The comments themselves |
| `misc/comments-test.md` | Test page for trying the form: https://travisdowns.github.io/misc/comments-test.html |

An entry looks like this (same shape Staticman produced, so old and new entries
render identically):

```yaml
_id: 6127d158-232a-4169-887d-c6fc477ee061
_parent: https://travisdowns.github.io/blog/2020/05/13/intel-zero-opt.html
name: Some Reader
email: 440068bee91299137007379cc7eb87c3   # MD5 of the address, or ""
message: Nice post!
replying_to_uid: ""                         # parent's _id for replies
date: 1791847835                            # epoch seconds
```

## The worker

Source: [travisdowns/comment-worker](https://github.com/travisdowns/comment-worker),
a fork of [zanechua/comment-worker](https://github.com/zanechua/comment-worker)
with Staticman-compatible output, personal access token auth and spam flagging.
Its README documents all settings. Locally it is cloned at `~/dev/comment-worker`.

Non-secret settings are in its `wrangler.toml`: repo `travisdowns/travisdowns.github.io`,
branch `master`, allowed origin `https://travisdowns.github.io`. The worker runs
on the Cloudflare free plan (100k requests/day, 10 ms CPU per request; waiting
on GitHub does not count as CPU).

A submission is flagged as likely spam, but still delivered as a PR, when the
honeypot field is filled or the Turnstile token is missing or fails
verification. Posts sent directly (curl, bots that skip the page) never have a
token, so they always arrive flagged. Nothing is ever silently dropped.

### Common operations

Run these in `~/dev/comment-worker` (wrangler is a dev dependency; log in once
with `npx wrangler login`):

```bash
npx wrangler deploy                      # deploy the current source
npx wrangler secret put GITHUB_TOKEN     # set/rotate a secret (prompts for the value)
npx wrangler secret list                 # names only; values cannot be read back
npx wrangler tail                        # live logs (errors, failed GitHub calls)
```

Test the deployed worker end to end (opens a real PR, flagged because there is
no Turnstile token; close it afterwards with `gh pr close <n> --delete-branch`):

```bash
curl -s -H 'Origin: https://travisdowns.github.io' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  https://comment-worker.comment-worker.workers.dev/api/handle/form \
  --data 'options[parent]=https%3A%2F%2Ftravisdowns.github.io%2Fmisc%2Fcomments-test.html&options[slug]=comments-test&fields[replying_to_uid]=&fields[message]=test&fields[name]=Test&fields[email]=&fields[hp]='
```

Success is `{"success":true}` with HTTP 201. Errors are
`{"success":false,"errorCode":"..."}`, which the form shows in its error modal.

### Testing locally without touching GitHub

`wrangler dev` reads `.dev.vars` (gitignored). Setting `GITHUB_API_URL` points
the worker at a mock GitHub API instead of the real one, and Cloudflare's
published Turnstile test keys avoid needing the real widget (which only works on
`travisdowns.github.io`):

| Test key | Value |
|---|---|
| Site key, invisible, always passes | `1x00000000000000000000BB` |
| Secret, always passes | `1x0000000000000000000000000000000AA` |
| Secret, always fails | `2x0000000000000000000000000000000AA` |

Build the blog with an override config that sets `staticman_url` to the local
worker and `turnstile.siteKey` to the test site key, serve `_site` on
`127.0.0.1:4000`, and set `CW_ALLOWED_ORIGINS=http://127.0.0.1:4000` in
`.dev.vars`.

## Moderation

- New comments are PRs by `travisdowns-bot` titled
  `Comment from <name> on <slug>`. Merge to publish.
- Suspected spam is titled `[likely spam] ...`, labeled `likely-spam`, and the
  PR body lists why. Close with `gh pr close <n> --delete-branch` so the branch
  does not linger (closing in the web UI leaves the branch behind).
- Typical spam: templated "In today's fast-paced world, staying informed..."
  news blurbs, Russian-language ads with links, and LLM-written generic praise
  ending in a commercial link. None of these filled the honeypot.

## Credentials

The repository is public. **No secret belongs in it.**

| Item | Where it lives | Sensitive | Notes |
|---|---|---|---|
| Turnstile site key `0x4AAAAAAFVGkvWgEX0SvbNz` | `_config.yml`, page HTML | No, public by design | Widget "Performance Matters comments", Invisible mode, hostname `travisdowns.github.io` |
| Turnstile secret key | Worker secret `TURNSTILE_SECRET_KEY` | Yes (low impact) | Lets the worker verify tokens; cannot be used to forge them. Rotate in the dashboard (Turnstile, the widget, Settings) |
| GitHub token for `travisdowns-bot` | Worker secret `GITHUB_TOKEN` | **Yes, highest** | Classic token with `repo` scope, no expiry; the bot is a collaborator on this repo. It reaches every repo the bot can push to, not just this one. A fine-grained token cannot replace it: those only reach repos owned by the token's own account. The narrower alternative is a GitHub App installed on this repo only (`GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY`, supported by the worker) |
| Wrangler login | `~/.config/.wrangler/config/default.toml` on the machine that logged in | Yes | OAuth access to the whole Cloudflare account. Revoke with `npx wrangler logout` or in the dashboard (My Profile, Access Management, Connected Applications) |
| Cloudflare account ID `1c93cf9ef893c67983ab794c3a15b981` | Dashboard and API URLs | No | Identifier only |

Worker secrets cannot be read back from Cloudflare. To get the Turnstile secret
again, fetch the widget with the API using wrangler's login token (refresh it by
running any wrangler command if it has expired):

```bash
TOK=$(grep -m1 '^oauth_token' ~/.config/.wrangler/config/default.toml | cut -d'"' -f2)
curl -s -H "Authorization: Bearer $TOK" \
  https://api.cloudflare.com/client/v4/accounts/1c93cf9ef893c67983ab794c3a15b981/challenges/widgets/0x4AAAAAAFVGkvWgEX0SvbNz \
  | jq -r .result.secret
```

## Privacy notes

- Invisible Turnstile requires the site to reference Cloudflare's
  [Turnstile Privacy Addendum](https://www.cloudflare.com/turnstile-privacy-policy/);
  the note under the form ("This form uses Cloudflare Turnstile") links to it.
- Commenter emails are stored as MD5 hashes in this public repo. Common
  addresses can be recovered by guessing, so they are only lightly obscured.

## History

From February 2020 the bridge was a [Staticman](https://github.com/eduardoboucas/staticman)
instance on Heroku (`staticman-travisdownsio.herokuapp.com`, set up as described
in the [now-with-comments](https://travisdowns.github.io/blog/2020/02/05/now-with-comments.html)
post). In June 2026 a $5 Heroku invoice failed (the card on file was declined),
and Heroku suspended and then permanently deleted the account on 2026-06-27,
taking the app, its RSA key and its config with it. Comments were moved to
comment-worker in October 2026. The reCAPTCHA configuration was removed at the
same time; its secret had been encrypted with the lost Staticman RSA key.
