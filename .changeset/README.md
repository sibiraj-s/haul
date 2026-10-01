# Changesets

Each user-facing change gets a changeset: a small Markdown file that says how it
bumps the version and what to put in the changelog.

```sh
npx changeset          # pick patch / minor / major and write a summary
```

Commit the file with the change. On `master`, the Release workflow keeps a
"Version Packages" pull request open that bumps `package.json` and updates
`CHANGELOG.md`. Merging it tags `v<version>`, creates the GitHub Release, and
attaches the DMG built by `build.sh`.
