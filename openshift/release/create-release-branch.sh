#!/usr/bin/env bash

# Synchs the OPERATOR_MIDSTREAM_BRANCH branch to master and then triggers CI
# Usage: update-to-head.sh

set -ex
OPENSHIFT_REMOTE=${OPENSHIFT_REMOTE:-openshift}
OPERATOR_UPSTREAM_BRANCH=${OPERATOR_UPSTREAM_BRANCH:-main}
OPERATOR_MIDSTREAM_BRANCH=${OPERATOR_MIDSTREAM_BRANCH:-release-next}
PIPELINE_VERSION=${PIPELINE_VERSION:-nightly} #0.28.2
TRIGGERS_VERSION=${TRIGGERS_VERSION:-nightly} #0.16.0
CATALOG_RELEASE_BRANCH=${CATALOG_RELEASE_BRANCH:-release-next} #release-v0.24
# RHOSP (Red Hat OpenShift Pipelines)
# RHOSP_VERSION=${RHOSP_VERSION:-$(date  +"%Y.%-m.%-d")-nightly}
RHOSP_VERSION=${RHOSP_VERSION:-1.6.0} # we need to keep this constant for now as, we cannot push generated csv on a daily basis (NT)
RHOSP_PREVIOUS_VERSION=${RHOSP_PREVIOUS_VERSION:-1.5.2}
OLM_SKIP_RANGE=${OLM_SKIP_RANGE:-\'>=1.5.0 <1.6.0\'}

function get_buildah_task() {
# The fetch task script will not pull buildah task from github repository
# as we have have made modifications in the buildah task in operator repository
# This function will preserve the buildah task from the previous release (clusterTask payload)
    buildah_dest_dir="cmd/openshift/operator/kodata/tekton-addon/${RHOSP_VERSION}/addons/02-clustertasks/buildah"
    mkdir -p ${buildah_dest_dir} || true
    task_path=${buildah_dest_dir}/buildah-task.yaml
    version_suffix="${RHOSP_VERSION//./-}"
    task_version_path=${buildah_dest_dir}/buildah-${version_suffix}-task.yaml

    cp -r cmd/openshift/operator/kodata/tekton-addon/1.5.0/addons/02-clustertasks/buildah/buildah-task.yaml ${buildah_dest_dir}
    sed \
        -e "s|^\(\s\+name:\)\s\+\(buildah\)|\1 \2-$RHOSP_VERSION|g"  \
        $task_path  > "$task_version_path"
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

# handle buildah task separately
get_buildah_task
# pull tasks
./hack/openshift/update-tasks.sh ${CATALOG_RELEASE_BRANCH} cmd/openshift/operator/kodata/tekton-addon/${RHOSP_VERSION} ${RHOSP_VERSION}

# add all other addons resources (clustertriggerbindings, consoleclidownload ...)
# from 1.5.0 dir (https://github.com/tektoncd/operator/tree/f2113b6092a4cb24ad2efd3c005fe97480070a00/cmd/openshift/operator/kodata/tekton-addon/1.5.0)
# TODO: move all addons into tekton-addon witout the version subdirectory
copy_static_addon_resources 1.5.0 ${RHOSP_VERSION}

# generate csv
BUNDLE_ARGS="--workspace operatorhub/openshift \
             --operator-release-version ${RHOSP_VERSION} \
             --channels stable,preview \
             --default-channel stable \
             --fetch-strategy-local \
             --upgrade-strategy-replaces \
             --operator-release-previous-version ${RHOSP_PREVIOUS_VERSION} \
             --olm-skip-range ${OLM_SKIP_RANGE}"

make operator-bundle

git add openshift OWNERS_ALIASES OWNERS cmd/openshift/operator/kodata operatorhub/openshift
git commit -m ":open_file_folder: Update openshift specific files."

git push -f ${OPENSHIFT_REMOTE} ${OPERATOR_MIDSTREAM_BRANCH}
