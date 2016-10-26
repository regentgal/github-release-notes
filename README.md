# github-release-notes

```
ruby releasenotes.rb generate --repo <path to the local repo> --from <last git tag> --to <current git tag> --github https://github.com/jetpackworkflow/checklistpro --gh_token <github token>
```

Generate a [Personal Access Token][] with the scope `repo` (Full
control of private repositories). This gives the script access to
search for commits in private repositories.

[Personal Access Token]: https://github.com/settings/tokens
