#!/bin/bash
set -eo pipefail

set -x
echo "${BUILD_DIR}"
cd "${BUILD_DIR}"
set +x

docker run --privileged -i --name worker --user builder \
  -e USER_ID=$(id -u) -e GROUP_ID=$(id -g) \
  -e GitHubMail="${GitHubMail}" -e GitHubName="${GitHubName}" -e GITHUB_TOKEN="${GITHUB_TOKEN}" \
  -e CIRCLE_PROJECT_USERNAME="${CIRCLE_PROJECT_USERNAME}" -e CIRCLE_PROJECT_REPONAME="${CIRCLE_PROJECT_REPONAME}" \
  -e CIRCLE_BRANCH="${CIRCLE_BRANCH}" -e CIRCLE_SHA1="${CIRCLE_SHA1}" \
  -e MANIFEST_BRANCH="${MANIFEST_BRANCH}" -e PBRP_BRANCH="${PBRP_BRANCH}" \
  -e USE_SECRET_BOOTABLE="${USE_SECRET_BOOTABLE}" -e SECRET_BR="${SECRET_BR}" \
  -e VERSION="${VERSION}" -e VENDOR="${VENDOR}" -e CODENAME="${CODENAME}" \
  -e BUILD_LUNCH="${BUILD_LUNCH}" -e FLAVOR="${FLAVOR}" \
  -e MAINTAINER="${MAINTAINER}" -e CHANGELOG="${CHANGELOG}" \
  -e TEST_BUILD="${TEST_BUILD}" -e PB_OFFICIAL="${PB_OFFICIAL}" \
  -e PB_ENGLISH="${PB_ENGLISH}" -e EXTRA_CMD="${EXTRA_CMD}" \
  -e BOT_API="${BOT_API}" -e GCF_AUTH_KEY="${GCF_AUTH_KEY}" \
  -e SFUserName="${SFUserName}" -e SFPassword="${SFPassword}" \
  -e BUILD_DIR="${BUILD_DIR}" \
  --workdir /home/builder/android/ \
  -v "${pwd}:/home/builder/android:rw,z" \
  -v "/home/builder/.ccache:/srv/ccache:rw,z" \
  fr3akyphantom/droid-builder:focal bash << EOF
set -vx
id
whoami
sudo whoami
pwd
cd "${BUILD_DIR}" && pwd
curl -L https://github.com/rokibhasansagar/pbrp_buildscripts/raw/master/common_builder.sh -o builder.sh
ls -lA .
set +vx
source builder.sh
EOF
