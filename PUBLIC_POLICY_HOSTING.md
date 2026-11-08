# Public policy pages

The repository now contains the ProSN privacy policy, account-deletion page,
community guidelines, and child-safety standards under `web/policy/`.

A GitHub Pages workflow publishes only these static policy pages. After this
change is merged to `main`, check the workflow run named **Publish ProSN policy
pages**. If GitHub Pages is not enabled for the repository, open
**Settings → Pages** and set the build/deployment source to **GitHub Actions**,
then rerun the workflow.

Expected URLs after a successful deployment:

- https://shalubano637-ship-it.github.io/ProEarn/policy/privacy-policy.html
- https://shalubano637-ship-it.github.io/ProEarn/policy/account-deletion.html
- https://shalubano637-ship-it.github.io/ProEarn/policy/community-guidelines.html
- https://shalubano637-ship-it.github.io/ProEarn/policy/child-safety.html

Do not submit these URLs in Play Console until the Pages deployment succeeds
and each page opens in a private/incognito browser without signing in.
