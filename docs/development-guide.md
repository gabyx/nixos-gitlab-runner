### Development Guide

This guide documents our procedures and policies for project maintenance tasks,
including managing our conventions, pull/merge-requests, continuous integration,
releasing.

## Commit Convention

We use the
[conventional commits](https://www.conventionalcommits.org/en/v1.0.0/)
specification for commit messages and pull/merge-request titles.

<!-- Additional 'scopes' should be described here.-->
<!-- ### Scopes -->

## Running the Tests

Additionaly you can run the interactive driver:

```bash
test="test-gitlab-runner-unstable";
just test "$test.driverInteractive"

./.output/package/$test.driverInteractive/bin/nixos-test-driver
```

Then in the interactive ipython shell you can lunch the individual services
like:

```bash
gitlab_runner.start()
```
