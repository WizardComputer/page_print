# Research: RubyGems trusted publishing for multi-gem GHA releases

**Ticket:** [#8](https://github.com/WizardComputer/page_print/issues/8)  
**Map:** [#7](https://github.com/WizardComputer/page_print/issues/7)  
**Repo:** `WizardComputer/page_print`  
**Researched:** 2026-07-26  
**Sources:** primary docs and source only (listed at end)

## Answer in one paragraph

Register **one** GitHub Actions trusted publisher on the existing `page_print` gem (not one per platform). Point it at owner `WizardComputer`, repo `page_print`, workflow filename `package.yml`, and environment `release`. In a tag-only publish job that `needs:` the three build jobs, set `permissions: { id-token: write, contents: write }`, `environment: release`, download the three `.gem` artifacts, run `rubygems/configure-rubygems-credentials@v2` (OIDC audience default `rubygems.org`), then `gem push` each file. Do **not** use `rubygems/release-gem` here — it runs `bundle exec rake release` (build + git tag), which does not fit prebuilt multi-platform artifacts.

## Multi-platform: one publisher covers all three gems

RubyGems trusted publishers bind to a **rubygem name** (`page_print`), not to a platform string.

These are three versions of the same gem name:

| Artifact | Gem name | Platform |
|----------|----------|----------|
| `page_print-X.Y.Z.gem` | `page_print` | `ruby` |
| `page_print-X.Y.Z-x86_64-linux.gem` | `page_print` | `x86_64-linux` |
| `page_print-X.Y.Z-arm64-darwin.gem` | `page_print` | `arm64-darwin` |

One trusted-publisher row on `page_print` authorizes short-lived `push_rubygem` API keys for that name. Pushing all three platforms in one job is supported and is how multi-platform repos (e.g. `ruby/prism`) do it.

You only need **multiple** trusted publishers if:

- multiple **workflow filenames** push (e.g. `release-linux.yml` and `release-mac.yml`), or
- multiple **gem names** share one workflow (e.g. monorepo).

For this repo: **one** publisher for `package.yml` is enough.

## Human setup: RubyGems UI

`page_print` already exists on RubyGems → use the **existing gem** path (not pending publishers).

1. Sign in as an owner of `page_print` at [rubygems.org](https://rubygems.org).
2. Open the gem → sidebar **Trusted publishers**  
   (`https://rubygems.org/gems/page_print/trusted_publishers`).
3. **Create** and fill:

   | Field | Value |
   |-------|--------|
   | Repository owner | `WizardComputer` |
   | Repository name | `page_print` |
   | Workflow filename | `package.yml` (basename only; must end in `.yml` / `.yaml`) |
   | Environment | `release` (recommended) |
   | Workflow repository owner/name | leave blank (workflow lives in this repo) |

4. Save. The publisher appears in the gem’s trusted-publisher list.

**GitHub environment (repo settings):**

1. Repo → Settings → Environments → create `release`.
2. Optional but recommended: required reviewers, and restrict the environment to the `v*` tag pattern / protected branches as your org allows.
3. The **job** that publishes must set `environment: release` so the OIDC token includes `environment: release`. If RubyGems has environment `release` configured, a job without that environment will fail claim matching.

No long-lived RubyGems API key and no OTP for CI once this is set.

Pending publishers (`https://rubygems.org/profile/oidc/pending_trusted_publishers`) are only for **first push of a brand-new gem name**. Not needed here.

## OIDC mechanics (what the job must satisfy)

Flow (from RubyGems guides + action source):

1. Job requests a GitHub OIDC JWT with audience `rubygems.org` (`id-token: write` required).
2. `rubygems/configure-rubygems-credentials` POSTs the JWT to  
   `https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token`.
3. RubyGems verifies signature (GitHub JWKS), finds a matching trusted publisher, checks an access policy built from claims, and returns a short-lived API key.
4. Key facts from [rubygems.org exchange controller](https://github.com/rubygems/rubygems.org/blob/master/app/controllers/api/v1/oidc/trusted_publisher_controller.rb):
   - **Scopes:** `push_rubygem` only
   - **TTL:** **15 minutes** from exchange
   - Key is written into the usual gem credentials path for subsequent `gem push`

### Claims RubyGems matches (GitHub Actions publisher)

From [`OIDC::TrustedPublisher::GitHubAction`](https://github.com/rubygems/rubygems.org/blob/master/app/models/oidc/trusted_publisher/github_action.rb):

| Claim / field | Match rule |
|---------------|------------|
| `repository` | `WizardComputer/page_print` |
| `repository_owner_id` | Numeric owner id at registration time (resurrection-safe) |
| `job_workflow_ref` | Workflow basename must be the registered file (e.g. `.../.github/workflows/package.yml@refs/tags/v0.1.6`) |
| `environment` | If publisher has environment set → JWT must equal it. If publisher environment is blank → any/no environment OK |
| `aud` | Host of RubyGems (`rubygems.org`); action default audience is `rubygems.org` |
| `iss` | `https://token.actions.githubusercontent.com` |

Same-repo workflows: policy allows the JWT’s `ref` **or** `sha` as the `@` suffix of `job_workflow_ref` (so tag pushes work: `refs/tags/v*`).

Reusable workflows in another repo need the optional Workflow Repository fields; not applicable here.

### Required workflow permissions

On the **publish job** (prefer job-level, not workflow-level):

```yaml
permissions:
  id-token: write   # mandatory for OIDC → RubyGems exchange
  contents: write   # only if this job also creates a GitHub Release / uploads assets
  # contents: read is enough if publish is gem-push only
```

Build jobs do **not** need `id-token: write`.

## Recommended pattern for this repo

**Do not use** `rubygems/release-gem@v1` for page_print. That action:

- runs `bundle exec rake release` (bundler gem tasks: build + git tag push)
- assumes a single gem built in-job

We already build three platform gems in separate jobs and upload artifacts. Match the official multi-artifact pattern used by [ruby/prism](https://github.com/ruby/prism/blob/main/.github/workflows/publish-gem.yml) and [dependabot-core](https://github.com/dependabot/dependabot-core/blob/main/.github/workflows/gems-release-to-rubygems.yml): **configure credentials + `gem push`**.

### Sketch to add to `.github/workflows/package.yml`

```yaml
  publish:
    name: Publish to RubyGems
    needs: [source, linux, darwin-arm64]
    if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment: release
    permissions:
      id-token: write
      contents: write   # drop to read if no GitHub Release in this job

    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4.7"

      - uses: actions/download-artifact@v4
        with:
          path: gems
          # current artifact names from package.yml:
          # page_print-source-gem, page_print-linux-gem, page_print-darwin-arm64-gem
          pattern: page_print-*-gem
          merge-multiple: true

      - name: Expect three platform gems
        run: |
          set -euo pipefail
          ls -la gems/
          test "$(find gems -name 'page_print-*.gem' | wc -l | tr -d ' ')" = "3"

      # Pin to a full SHA in production (action authors recommend it).
      - uses: rubygems/configure-rubygems-credentials@v2
        # defaults: trusted-publisher=true, audience=rubygems.org, gem-server=https://rubygems.org

      - name: gem push all platforms
        run: |
          set -euo pipefail
          for gem in gems/page_print-*.gem; do
            echo "Pushing ${gem}"
            gem push "${gem}"
          done
```

Notes for implementers:

- Gate publish with `if:` on tags so PR / `workflow_dispatch` package runs do not attempt OIDC publish.
- Exchange + three pushes easily fit inside the **15-minute** API key TTL.
- `gem push` needs no OTP when the short-lived trusted-publisher key is configured.
- Optional: create GitHub Release and attach the same `.gem` files after a successful push (map destination); still one OIDC session.
- Prefer pinning `configure-rubygems-credentials` to a commit SHA (e.g. v2.1.0 → `dc5a8d8553e6ee01fc26761a49e99e733d17954a` as of 2026-06).

### What `configure-rubygems-credentials` does

With no `api-token` / `role-to-assume` inputs it defaults to trusted publishing:

1. `core.getIDToken("rubygems.org")`
2. Exchange at `/api/v1/oidc/trusted_publisher/exchange_token`
3. Write credentials so `gem` / `bundler` pick them up

Inputs (defaults): `audience: rubygems.org`, `gem-server: https://rubygems.org`.

## Failure modes

| Situation | What happens |
|-----------|----------------|
| Missing `id-token: write` | Action cannot mint JWT; exchange never starts |
| Workflow filename mismatch (e.g. registered `release.yml`, job lives in `package.yml`) | Exchange 404-style: no trusted publisher for this workflow |
| Environment set on RubyGems as `release`, job omits `environment:` | Access policy fails environment claim |
| Job uses `environment: release`, publisher has no environment | OK (nil environment publisher matches any) |
| Wrong owner/repo | No matching publisher |
| Fork PR workflows | Fork runs cannot use the upstream trusted publisher; third-party PR events generally cannot obtain usable OIDC for upstream publishing. Keep publish on `push` tags only |
| Tag cut from a non-default branch | **Works** if that commit contains `.github/workflows/package.yml` as registered. GHA runs the workflow at the tag ref; claims use `refs/tags/v…` / commit SHA |
| Tag commit lacks `package.yml` or renames the file | Job missing or filename no longer matches publisher |
| `workflow_dispatch` without tag `if:` guard | Could publish whatever is on the default branch checkout if someone enables it — gate with `if:` and/or environment reviewers |
| Anyone who can change `package.yml` on a pushable ref | Equivalent to holding push rights for the gem; review that file carefully; use environment required reviewers |
| Gem version already on RubyGems | `gem push` fails (repush denied); job should fail closed unless you explicitly skip already-published |
| Slow job > 15 min after credential step | API key expires mid-push; keep publish job to download + push only |
| `release-gem` action used by mistake | Tries `rake release` / tagging; wrong shape for multi-artifact publish |
| Owner removed from gem but trusted publisher left | Publishers are on the **gem**, not the user — audit publishers when offboarding |

## Explicit non-goals / open for humans

- Creating the trusted publisher and `release` environment on RubyGems/GitHub (needs owner UI / org admin).
- Whether the first live tag is a dry-run verification before deleting `bin/release` (map “Not yet specified”).
- Exact GitHub Release notes step (separate from OIDC).

## Primary links

| Topic | URL |
|-------|-----|
| Trusted Publishing guide | https://guides.rubygems.org/trusted-publishing/ |
| Announcement | https://blog.rubygems.org/2023/12/14/trusted-publishing.html |
| `configure-rubygems-credentials` | https://github.com/rubygems/configure-rubygems-credentials |
| `release-gem` (single-gem `rake release`; not our shape) | https://github.com/rubygems/release-gem |
| GitHub OIDC overview | https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect |
| GitHub environments | https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/using-environments-for-deployment |
| Publisher claim matching (source) | https://github.com/rubygems/rubygems.org/blob/master/app/models/oidc/trusted_publisher/github_action.rb |
| Token exchange (source) | https://github.com/rubygems/rubygems.org/blob/master/app/controllers/api/v1/oidc/trusted_publisher_controller.rb |
| Multi-artifact push example | https://github.com/ruby/prism/blob/main/.github/workflows/publish-gem.yml |
| PyPI security model (cross-ref from RubyGems guide) | https://docs.pypi.org/trusted-publishers/security-model/ |
