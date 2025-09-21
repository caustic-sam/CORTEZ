DEVELOPER GUIDE
===============

This guide explains how to safely update `main`, prepare releases, and perform common maintenance tasks for Cortex. It's written for a developer with shell access to the repo and typical `git`/`gh` tooling.

1) Branch workflow

- Create feature branches from `main`: `git checkout -b feature/short-description main`.
- Keep changes small and include a short test recipe in PR descriptions.
- Open a PR targeting `main`. Wait for review and CI before merging.
- After merge, delete the feature branch both locally and remotely:

```bash
git push origin --delete feature/short-description
git branch -d feature/short-description
```

2) Updating `main` with hotfixes or merges

- For a hotfix, create `fix/...` branch and open a PR as above.
- To incorporate a remote branch locally and ensure `main` is current:

```bash
git fetch origin
git checkout main
git pull --rebase origin main
```

- If you need to merge a completed feature branch locally (non-PR flow):

```bash
git checkout main
git fetch origin
git merge --no-ff feature/branch-name -m "Merge feature/branch-name: description"
git push origin main
```

3) Releases

- Tag a release (use annotated tags):

```bash
git tag -a vYYYY.MM.DD -m "Release vYYYY.MM.DD: short notes"
git push origin vYYYY.MM.DD
```

- For named releases like `UNBOUND`, use a human-friendly tag:

```bash
git tag -a UNBOUND -m "Release: UNBOUND - notes"
git push origin UNBOUND
```

4) Permissions and runtime data

- Services should write runtime data outside the repository (e.g., `/var/lib/service` or `/srv/data`).
- If runtime data is accidentally committed or created under the repo, use `scripts/fix-perms.sh` to recover tracked files and add the runtime paths to `.gitignore`.

5) Emergency permission fix (quick)

```bash
# conservative: only change tracked files owned by root
git ls-files -z | xargs -0 -I{} sh -c 'stat -c "%U %n" "{}"' 2>/dev/null | awk '$1=="root" {print substr($0, index($0,$2))}' | sed 's/^\.\///' | sort -u | xargs -r -I{} sudo chown $(whoami):$(whoami) "{}"
```

6) Branch protection and defaults (admin tasks)

- Consider enabling branch protection for `main` (require PRs, status checks).
- Use the GitHub UI or `gh` to set protection rules.

7) Helpful commands

- Update local origin HEAD after changing default branch on GitHub:

```bash
git remote set-head origin -a
```

- Run the permissions helper:

```bash
sudo ./scripts/fix-perms.sh
```

8) Who to contact

- If you're unsure about merging a large change or need a rollback plan, open a PR and add `@caustic-sam` as reviewer.

---

Keep this file short and update as the project's practices evolve.
