#!/bin/bash
set -eo pipefail
###
#
#  Semi-AIO Script for Building PitchBlack Recovery in CircleCI
#
#  Copyright (C) 2019-2020, Rokib Hasan Sagar <rokibhasansagar2014@outlook.com>
#                           PitchBlack Recovery Project <pitchblackrecovery@gmail.com>
#
###

echo -e "\n \u261e SANITY CHECKS...\n"
[[ -z $GitHubMail ]] && ( echo -e "You haven't configured GitHub E-Mail Address." && exit 1 )
[[ -z $GitHubName ]] && ( echo -e "You haven't configured GitHub Username." && exit 1 )
[[ -z $GITHUB_TOKEN ]] && ( echo -e "You haven't configured GitHub Token.\nWithout it, recovery can't be published." && exit 1 )
[[ -z $MANIFEST_BRANCH ]] && ( echo -e "You haven't configured PitchBlack Recovery Project Manifest Branch." && exit 1 )
[[ -z $VENDOR ]] && ( echo -e "You haven't configured Vendor name." && exit 1 )
[[ -z $CODENAME ]] && ( echo -e "You haven't configured Device Codename." && exit 1 )
[[ -z $BUILD_LUNCH && -z $FLAVOR ]] && ( echo -e "Set at least one variable. BUILD_LUNCH or FLAVOR." && exit 1 )

echo -e "\n \u2714 Making Sure We Are On The Right Path...\n"
export BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)"
cd "${BUILD_DIR}"

echo -e "\n \u2730 Setting GitAuth Infos...\n"
git config --global user.email $GitHubMail
git config --global user.name $GitHubName
git config --global credential.helper store
git config --global color.ui true

if [[ "${CIRCLE_PROJECT_USERNAME}" == "PitchBlackRecoveryProject" ]]; then
  echo -e "\n Use Google Git Cookies for Smooth repo-sync\n"
  git clone -q "https://$GITHUB_TOKEN@github.com/PitchBlackRecoveryProject/google-git-cookies.git" &> /dev/null
  bash google-git-cookies/setup_cookies.sh
  rm -rf google-git-cookies
fi

echo -e "\n \u2730 Using a keepalive shell so that it can bypass CI Termination on output freeze\n"
[[ ! -d /tmp ]] && mkdir -p /tmp
# Don't Use EOF as the docker command with fetch it
cat << EOS > /tmp/keepalive.sh
#!/bin/bash
echo \$$ > /tmp/keepalive.pid
while true; do
  echo "." && sleep 300
done
EOS
chmod a+x /tmp/keepalive.sh

# As the Remote Docker has only 2x1 CPU Threads whereas normal CI Build has 4x9, This is configured for both
if [[ $(nproc --all) == 2 ]]; then
  THREADCOUNT=7
else
  THREADCOUNT=$(nproc --all)
fi

echo -e "\n \u21af Initializing PBRP repo sync..."
repo init -q -u https://github.com/PitchBlackRecoveryProject/manifest_pb.git -b ${MANIFEST_BRANCH} --depth 1
/tmp/keepalive.sh & repo sync -c -q --force-sync --no-clone-bundle --no-tags -j$THREADCOUNT
kill -s SIGTERM $(cat /tmp/keepalive.pid)

# Clean unneeded files, Remove them from manifest in the future
rm -rf development/apps/ development/samples/ packages/apps/

# SAFEKEEPING, use proper pb-10.0
echo -e "\n \u2295 Using Proper Vendor Repo for android-10.0 platform\n"
if [[ "${MANIFEST_BRANCH}" == "android-10.0" ]]; then
  rm -rf vendor/pb && git clone --quiet https://github.com/PitchBlackRecoveryProject/vendor_pb -b pb-10.0 --depth 1 vendor/pb
  # It is recommended to add vendorsetup script in DT, not in vendor in android-10.0
  rm vendor/pb/vendorsetup.sh || true
fi

if [[ ! -f vendor/pb/pb_build.sh ]]; then
  echo -e "\n \u2727 Hax for fixing recoveryimage build with less complexity\n"
  cp -a vendor/utils/pb_build.sh vendor/pb/pb_build.sh
  chmod +x vendor/pb/pb_build.sh
fi

echo -e "\n \u21af Getting the Device Tree for ${CODENAME} on place...\n"
if [[ "${CIRCLE_PROJECT_USERNAME}" == "PitchBlackRecoveryProject" ]]; then
  git clone --quiet https://$GITHUB_TOKEN@github.com/PitchBlackRecoveryProject/${CIRCLE_PROJECT_REPONAME} -b ${CIRCLE_BRANCH} device/${VENDOR}/${CODENAME}
else
  git clone --quiet https://$GITHUB_TOKEN@github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME} -b ${CIRCLE_BRANCH} device/${VENDOR}/${CODENAME}
fi

if [[ -n ${USE_SECRET_BOOTABLE} ]]; then
  echo -e "\n \u2663 DEVS ONLY: Using Experimental bootable Repository for Alpha Builds...\n"
  [[ -n ${PBRP_BRANCH} ]] && unset PBRP_BRANCH
  [[ -z ${SECRET_BR} ]] && SECRET_BR="android-9.0"
  rm -rf bootable/recovery
  git clone --quiet https://$GITHUB_TOKEN@github.com/PitchBlackRecoveryProject/pbrp_recovery_secrets -b ${SECRET_BR} --single-branch bootable/recovery
elif [[ -n ${PBRP_BRANCH} ]]; then
  rm -rf bootable/recovery
  git clone --quiet https://github.com/PitchBlackRecoveryProject/android_bootable_recovery -b ${PBRP_BRANCH} --single-branch bootable/recovery
fi

if [[ -n $EXTRA_CMD ]]; then
  eval "$EXTRA_CMD"
  cd "${BUILD_DIR}"
fi

echo -e "\n \u269d Preparing Delicious Lunch...\n"
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
if [[ -n $FLAVOR ]]; then
  lunch omni_${CODENAME}-${FLAVOR}
elif [[ -n $BUILD_LUNCH ]]; then
  # "BUILD_LUNCH" is Depricated, Use "FLAVOR" Globally
  lunch ${BUILD_LUNCH}
fi

echo -e "\n [i] Not removing the .repo folder from now on, We have abundant space\n"
# Keep the whole .repo/manifests folder
#cp -a .repo/manifests ${BUILD_DIR}/
#echo "Cleaning up the .repo, no use of it now"
#rm -rf .repo
#mkdir -p .repo && mv ${BUILD_DIR}/manifests .repo/ && ln -s .repo/manifests/default.xml .repo/manifest.xml

echo -e "\n \u269B Starting the Android Build System with PitchBlack Recipe...\n"
/tmp/keepalive.sh & make -j$THREADCOUNT recoveryimage
kill -s SIGTERM $(cat /tmp/keepalive.pid)
echo -e "\n \u2668 Fresh and Hot PitchBlack-Flavored Recovery is Served.\n"

echo -e "\n \u269d Ready to Deploy\n"
export TEST_BUILDFILE="$(find ${BUILD_DIR}/out/target/product/${CODENAME}/PBRP-${CODENAME}-*-UNOFFICIAL.zip 2>/dev/null)"
export BUILDFILE="$(find ${BUILD_DIR}/out/target/product/${CODENAME}/PBRP-${CODENAME}-*-OFFICIAL.zip 2>/dev/null)"
export BUILD_FILE_TAR="$(find ${BUILD_DIR}/out/target/product/${CODENAME}/*.tar 2>/dev/null)"
export UPLOAD_PATH="${BUILD_DIR}/out/target/product/${CODENAME}/upload/"
echo "${TEST_BUILDFILE}"
echo "${UPLOAD_PATH}"
mkdir -p "${UPLOAD_PATH}"

if [[ -n ${BUILD_FILE_TAR} ]]; then
  echo "Samsung's Odin Tar available: $BUILD_FILE_TAR"
  cp ${BUILD_FILE_TAR} ${UPLOAD_PATH}
fi

if [[ "${CIRCLE_PROJECT_USERNAME}" == "PitchBlackRecoveryProject" ]] && [[ -n $BUILDFILE ]]; then
    echo "Got the Official Build: $BUILDFILE"
    sudo chmod a+x vendor/utils/pb_deploy.sh
    # This needs to minify and/or unify by sourcing
    ./vendor/utils/pb_deploy.sh ${CODENAME} ${SFUserName} ${SFPassword} ${GITHUB_TOKEN} ${VERSION} ${MAINTAINER}
    cp $BUILDFILE $UPLOAD_PATH
    export BUILDFILE=$(find ${BUILD_DIR}/out/target/product/${CODENAME}/recovery.img 2>/dev/null)
    cp $BUILDFILE $UPLOAD_PATH
    ghr -t ${GITHUB_TOKEN} -u ${CIRCLE_PROJECT_USERNAME} -r ${CIRCLE_PROJECT_REPONAME} -n "Latest Release for $(echo $CODENAME)" -b "PBRP $(echo $VERSION)" -c ${CIRCLE_SHA1} -delete ${VERSION} ${UPLOAD_PATH}
elif [[ $TEST_BUILD == "true" ]] && [[ -n $TEST_BUILDFILE ]]; then
  echo "Got the Unofficial Build: $TEST_BUILDFILE"
  export TEST_BUILDIMG="$(find ${BUILD_DIR}/out/target/product/${CODENAME}/recovery.img 2>/dev/null)"
  if [[ $USE_SECRET_BOOTABLE == 'true' ]]; then
    cp $TEST_BUILDIMG recovery.img
    TEST_IT=$(curl -F'file=@recovery.img' https://0x0.st)
  else
    cp "$TEST_BUILDFILE" "$UPLOAD_PATH"
    cp "$TEST_BUILDIMG" "$UPLOAD_PATH"
  fi
  ghr -t ${GITHUB_TOKEN} -u ${CIRCLE_PROJECT_USERNAME} -r ${CIRCLE_PROJECT_REPONAME} \
    -n "Test Release for $(echo $CODENAME)" -b "PBRP $(echo $VERSION)" -c ${CIRCLE_SHA1} -delete \
    ${VERSION}-test "${UPLOAD_PATH}"
  echo -e "\n\nAll Done Gracefully\n\n"
else
  echo -e "\n \u2620 Something Wrong with your upload system. Please fix it."
fi

# SEND NOTIFICATION TO MAINTAINERS, AVAILABLE FOR TEAM DEVS ONLY
if [[ "${CIRCLE_PROJECT_USERNAME}" == "PitchBlackRecoveryProject" ]] && [[ ! -z $TEST_BUILDFILE ]]; then
  echo -e "\nSending the Test build info in Maintainer Group\n"
  if [[ $USE_SECRET_BOOTABLE == 'true' ]]; then
    TEST_LINK="${TEST_IT}"
  else
    TEST_LINK="https://github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/releases/download/${VERSION}-test/$(echo $TEST_BUILDFILE | awk -F'[/]' '{print $NF}')"
  fi
  MAINTAINER_MSG="PitchBlack Recovery for \`${VENDOR}\` \`${CODENAME}\` is available Only For Testing Purpose\n\n"
  if [[ ! -z $MAINTAINER ]]; then MAINTAINER_MSG=${MAINTAINER_MSG}"Maintainer: ${MAINTAINER}\n\n"; fi
  if [[ ! -z $CHANGELOG ]]; then MAINTAINER_MSG=${MAINTAINER_MSG}"Changelog:\n"${CHANGELOG}"\n\n"; fi
  MAINTAINER_MSG=${MAINTAINER_MSG}"Go to ${TEST_LINK} to download it."
  if [[ $USE_SECRET_BOOTABLE == 'true' ]]; then
    cd vendor/utils; python3 telegram.py -c "-1001465331122" -M "$MAINTAINER_MSG" -m "HTML"; cd $DIR/work
  else
    cd vendor/utils; python3 telegram.py -c "-1001228903553" -M "$MAINTAINER_MSG" -m "HTML"; cd $DIR/work
  fi
fi
echo -e "\n\nAll Done Gracefully\n\n"

