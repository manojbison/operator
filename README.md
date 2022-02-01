# Openshift TektonCD operator

This repository holds Openshift's fork of
[`tektoncd/operator`](https://github.com/tektoncd/operator) with additions and
fixes needed only for the OpenShift side of things.

## Creating a Release branch

1. Set the following environment variables

  ```bash
  export OPERATOR_UPSTREAM_BRANCH=release-v0.50.x
  export OPERATOR_MIDSTREAM_BRANCH=release-v0.50.x
  export PIPELINE_VERSION=v0.28.3
  export TRIGGERS_VERSION=v0.16.1
  export CATALOG_RELEASE_BRANCH=release-v0.28
  ```

1. Run `create-release-branch` script

  ```bash
  ./openshift/release/create-release-branch.sh
  ```

### Creating Tags

1. each time we make a release (pathc or minor release) on a `release-vn.n.x` branch merge the necessary pull-requests (cherry picks)
   then tag the commit and push the tag to `github.com/openshift/tektoncd-operator`.

   **eg:**

  ```bash
   git tag v0.50.0 <commit sha>
   git push openshift c0.50.0
  ```

## How this repository works ?

The `master` branch holds up-to-date specific [openshift files](./openshift)
that are necessary for CI setups and maintaining it. This includes:

- Scripts to create a new release branch from `upstream`
- CI setup files
  - tests scripts

Each release branch holds the upstream code for that release and our
openshift's specific files.

## CI Setup

For the CI setup, two repositories are of importance:

- This repository
- [openshift/release](https://github.com/openshift/release) which
  contains the configuration of CI jobs that are run on this
  repository

All of the following is based on OpenShift’s CI operator
configs. General understanding of that mechanism is assumed in the
following documentation.
