#!/usr/bin/env bash

# Synchs the OPERATOR_MIDSTREAM_BRANCH branch to master and then triggers CI
# Usage: update-to-head.sh

set -ex
OPENSHIFT_REMOTE=${OPENSHIFT_REMOTE:-openshift}
OPERATOR_UPSTREAM_BRANCH=${OPERATOR_UPSTREAM_BRANCH:-main}
OPERATOR_MIDSTREAM_BRANCH=${OPERATOR_MIDSTREAM_BRANCH:-release-next}
PIPELINE_VERSION=${PIPELINE_VERSION:-nightly} #0.28.3
TRIGGERS_VERSION=${TRIGGERS_VERSION:-nightly} #0.16.0
CATALOG_RELEASE_BRANCH=${CATALOG_RELEASE_BRANCH:-release-next} #release-v0.24
# RHOSP (Red Hat OpenShift Pipelines)
# RHOSP_VERSION=${RHOSP_VERSION:-$(date  +"%Y.%-m.%-d")-nightly}
RHOSP_VERSION=${RHOSP_VERSION:-1.6.0} # we need to keep this constant for now as, we cannot push generated csv on a daily basis (NT)
RHOSP_PREVIOUS_VERSION=${RHOSP_PREVIOUS_VERSION:-1.5.2}
OLM_SKIP_RANGE=${OLM_SKIP_RANGE:-\'>=1.5.0 <1.6.0\'}
LOCALLY_MANAGED_CLUSTERTASKS=(buildah openshift-client)

function get_locally_managed_tasks() {
  # The fetch task script will not pull LOCALLY_MANAGED_CLUSTERTASKS tasks task from github repository
  # as we have have made modifications in these tasks in operator repository
  # This function will preserve these tasks from the previous release (clusterTask payload)

  src_dir="cmd/openshift/operator/kodata/tekton-addon/1.5.0/addons/02-clustertasks"
  dest_dir="cmd/openshift/operator/kodata/tekton-addon/${RHOSP_VERSION}/addons/02-clustertasks"
  echo $dest_dir
  for ct in ${LOCALLY_MANAGED_CLUSTERTASKS[*]}; do
    echo "copying clustertask: $ct"

    ct_src_dir=${src_dir}/${ct}
    ct_dest_dir=${dest_dir}/${ct}
    mkdir -p ${ct_dest_dir} || true

    ct_filename=${ct}-task.yaml
    ct_src_filepath=${ct_src_dir}/${ct_filename}
    ct_dest_filepath=${ct_dest_dir}/${ct_filename}

    cp ${ct_src_filepath} ${ct_dest_filepath}

    version_suffix="${RHOSP_VERSION//./-}"
    ct_versioned_filename=${ct}-${version_suffix}-task.yaml
    ct_versioned_dest_filepath=${ct_dest_dir}/${ct_versioned_filename}

    # create clustertask copy with versioned clustertask name (eg: name: buildah-1-6-0 from name: buildah)
    sed \
        -e "s|^\(\s\+name:\)\s\+\("${ct}"\)|\1 \2-${version_suffix}|g"  \
        ${ct_dest_filepath}  > "${ct_versioned_dest_filepath}"
  done
}

# copy all addon other than clustertasks into the nightly addon payload directory
function copy_static_addon_resources() {
  src_version=${1}
  dest_version=${2}
  src_dir="cmd/openshift/operator/kodata/tekton-addon/${src_version}"
  dest_dir="cmd/openshift/operator/kodata/tekton-addon/${dest_version}"

  cp -r ${src_dir}/optional ${dest_dir}/optional

  addons_dir_src=${src_dir}/addons
  addons_dir_dest=${dest_dir}/addons

  for item in $(ls ${addons_dir_src} | grep -v 02-clustertasks); do
    cp -r ${addons_dir_src}/${item} ${addons_dir_dest}/${item}
  done
  # copy rbac for clustertasks
  cp ${addons_dir_src}/02-clustertasks/*.yaml ${addons_dir_dest}/02-clustertasks/
}

function set_version_label() {
  operator_version=v${1}
  sed -i -e 's/\(operator.tekton.dev\/release\): "devel"/\1: '${operator_version}'/g' -e 's/\(app.kubernetes.io\/version\): "devel"/\1: '${operator_version}'/g' -e 's/\(version\): "devel"/\1: '${operator_version}'/g' -e 's/\("-version"\), "devel"/\1, '${operator_version}'/g' config/base/*.yaml
  sed -i -e 's/\(operator.tekton.dev\/release\): "devel"/\1: '${operator_version}'/g' -e 's/\(app.kubernetes.io\/version\): "devel"/\1: '${operator_version}'/g' -e 's/\(version\): "devel"/\1: '${operator_version}'/g' -e 's/\("-version"\), "devel"/\1, '${operator_version}'/g' config/openshift/base/*.yaml
  sed -i -e 's/\(operator.tekton.dev\/release\): "devel"/\1: '${operator_version}'/g' -e 's/\(app.kubernetes.io\/version\): "devel"/\1: '${operator_version}'/g' -e 's/\(version\): "devel"/\1: '${operator_version}'/g' -e 's/\("-version"\), "devel"/\1, '${operator_version}'/g' config/openshift/overlays/default/*.yaml
}

# add release specific patches
function apply_patches() {
  mkdir -p openshift/patches || true
  if [[ -d openshift/patches ]];then
      for f in openshift/patches/*.patch;do
          [[ -f ${f} ]] || continue
          git am ${f}
      done
  fi
}

# Reset ${OPERATOR_MIDSTREAM_BRANCH} to upstream/${OPERATOR_UPSTREAM_BRANCH}.
git fetch upstream ${OPERATOR_UPSTREAM_BRANCH}
git checkout upstream/${OPERATOR_UPSTREAM_BRANCH} --no-track -B ${OPERATOR_MIDSTREAM_BRANCH}

# Update openshift's master and take all needed files from there.
git fetch ${OPENSHIFT_REMOTE} master
git checkout FETCH_HEAD openshift OWNERS_ALIASES OWNERS .tekton

# Add payload
make get-releases TARGET='openshift' \
                  PIPELINES=${PIPELINE_VERSION} \
                  TRIGGERS=${TRIGGERS_VERSION}

# copy locally managed tasks (eg: buildah, openshift-client)
get_locally_managed_tasks

# pull tasks
./hack/openshift/update-tasks.sh ${CATALOG_RELEASE_BRANCH} cmd/openshift/operator/kodata/tekton-addon/${RHOSP_VERSION} ${RHOSP_VERSION}

# add all other addons resources (clustertriggerbindings, consoleclidownload ...)
# from 1.5.0 dir (https://github.com/tektoncd/operator/tree/f2113b6092a4cb24ad2efd3c005fe97480070a00/cmd/openshift/operator/kodata/tekton-addon/1.5.0)
# TODO: move all addons into tekton-addon witout the version subdirectory
copy_static_addon_resources 1.5.0 ${RHOSP_VERSION}

# set operator version in operator resources
set_version_label ${RHOSP_VERSION}

git add openshift OWNERS_ALIASES OWNERS cmd/openshift/operator/kodata config operatorhub/openshift
git commit -m ":open_file_folder: Update openshift specific files."

apply_patches

# generate csv
export BUNDLE_ARGS="--workspace operatorhub/openshift \
             --operator-release-version ${RHOSP_VERSION} \
             --channels stable,preview \
             --default-channel stable \
             --fetch-strategy-local \
             --upgrade-strategy-replaces \
             --operator-release-previous-version ${RHOSP_PREVIOUS_VERSION} \
             --olm-skip-range ${OLM_SKIP_RANGE}"
rm -rf operatorhub/openshift/release-artifacts/bundle || true
make operator-bundle

git add openshift OWNERS_ALIASES OWNERS cmd/openshift/operator/kodata config operatorhub/openshift
git commit -m ":open_file_folder: Update openshift operator bundle."

git push -f ${OPENSHIFT_REMOTE} ${OPERATOR_MIDSTREAM_BRANCH}
