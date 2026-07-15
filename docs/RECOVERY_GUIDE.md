# Lamfa Recovery Guide

Every scenario below is detected automatically by menu 9 (Backup and recovery).
This page is the reference version. All listed steps PRESERVE your work;
Lamfa never suggests a data-discarding command in Beginner Mode.

## Merge stopped on a conflict

Both branches changed the same lines. Your work is safe.
1. Open each conflicted file; keep the correct content (markers `<<<<<<<`/`>>>>>>>`).
2. Stage the resolved files, commit - the merge completes.
3. To back out instead: `git merge --abort` returns to the pre-merge state.

## Rebase stopped

1. Resolve + stage the conflicted files, continue the rebase.
2. To cancel entirely: `git rebase --abort` - nothing committed is lost.

## Cherry-pick / revert stopped

Same pattern: resolve + stage + continue, or `--abort` to back out.

## Detached HEAD

You are standing on a commit, not a branch; new commits here are easy to lose.
1. If you committed something you want to keep: create a branch RIGHT HERE first.
2. Switch back to a normal branch.

## Diverged branch (ahead AND behind)

Your branch and its upstream each have commits the other lacks. Lamfa never
merges or rebases this automatically.
1. Inspect both sides (history view).
2. A merge keeps both histories; ask a teammate if unsure.

## No upstream

Pull/push have no defined target. Publish the branch (push with upstream
creation - Lamfa offers this automatically on first push).

## Push rejected

Someone pushed before you. Fetch, pull safely (fast-forward), and if the
branches diverged, see "Diverged branch". Your local commits stay intact.

## Stash apply conflicted

The stash was NOT deleted. Resolve the conflicts, then drop the stash manually.

## Wrong Docker context

Every Docker action targets the machine of the CURRENT context. Menu 7 shows
the context in the title and requires typed confirmation to switch. If you
pushed/built against the wrong machine: switch back, and clean up on the
machine that received the action.

## Wrong GitHub account

Menu 10 shows the active gh account. Switch accounts there; then re-check
repository access (menu 5 actions verify against the exact remote).

## Registered folder missing

The repository folder was moved or deleted outside Lamfa. Re-register it at
its new location (registrations never delete files).

## Last resort - full local backup

Menu 9 -> Git bundle backup writes the WHOLE history into one verified file,
restorable with `git clone <file.bundle>`. It does not replace pushing commits.
