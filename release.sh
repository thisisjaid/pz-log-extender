#!/usr/bin/env bash

# release.sh prepares mod files from src to Zomboid/Workshop folder.
#
# Copyright (c) 2023 Pavel Korotkiy (outdead).
# Use of this source code is governed by the MIT license.
#
# Usage: ./release.sh <version> [stage]
#   version  Semantic version, e.g. 0.14.0
#   stage    prod (default) | test | local
#
# Examples:
#   ./release.sh 0.14.0              # prod release
#   ./release.sh 0.14.0 test         # test release
#   ./release.sh 0.14.0 local        # local install for testing

MOD_VERSION="$1"
if [ -z "${MOD_VERSION}" ]; then echo "MOD_VERSION is not set. Use ./release.sh 0.0.0 [stage]" >&2; exit 1; fi

MOD_STAGE="$2"
if [ -z "${MOD_STAGE}" ]; then MOD_STAGE="prod"; fi

case ${MOD_STAGE} in
  local|test|prod)
    ;;
  *)
    echo "[  ER  ] Incorrect stage \"${MOD_STAGE}\". Use: prod, test, local" >&2; exit 1 ;;
esac

WORKSHOP_DIR="b42_${MOD_STAGE}"
SRC_DIR="src/b42"

MOD_NAME="B42LogExtender"
if [ "${MOD_STAGE}" == "test" ] || [ "${MOD_STAGE}" == "local" ]; then
  MOD_NAME="B42LogExtenderTest"
fi

echo "[ INFO ] Preparing ${MOD_NAME} release v${MOD_VERSION} (stage=${MOD_STAGE})"

RELEASE_NAME="${MOD_NAME}-${MOD_VERSION}"
RELEASE_DIR_WORKSHOP=".tmp/release/${RELEASE_NAME}"
RELEASE_DIR_MOD_HOME="${RELEASE_DIR_WORKSHOP}/mods/${MOD_NAME}"

function remove_old_release() {
  rm -rf .tmp/release
  rm -rf ~/Zomboid/Workshop/"${MOD_NAME}"
  if [ "${MOD_STAGE}" == "local" ]; then
    rm -rf ~/Zomboid/mods/"${MOD_NAME}"
  fi
}

function create_folders() {
  mkdir -p .tmp/release
  touch .tmp/release/checksum.txt
}

function make_release() {
  local dir_workshop="${RELEASE_DIR_WORKSHOP}"
  local dir_mod_home="${RELEASE_DIR_MOD_HOME}"
  local dir_b42="${dir_mod_home}/42"

  mkdir -p "${dir_b42}"

  cp "workshop/${WORKSHOP_DIR}/workshop.txt" "${dir_workshop}"
  cp workshop/preview.png "${dir_workshop}/preview.png"

  # Root: mod.info + poster for PZ mod discovery
  cp "workshop/${WORKSHOP_DIR}/mod.info" "${dir_mod_home}/mod.info"
  cp workshop/poster.png "${dir_mod_home}/poster.png"

  # 42/: version-scoped content — not loaded by B41
  cp "workshop/${WORKSHOP_DIR}/mod.info" "${dir_b42}/mod.info"
  cp workshop/poster.png "${dir_b42}/poster.png"
  cp -r "${SRC_DIR}" "${dir_b42}/media"
  cp LICENSE "${dir_b42}"
  cp README.md "${dir_b42}"
  cp CHANGELOG.md "${dir_b42}"
}

function compress_release() {
  local repo_root
  repo_root="$(pwd)"
  local release_dir="${repo_root}/.tmp/release"

  ( cd "${RELEASE_DIR_WORKSHOP}/mods" && \
    tar -zcvf "${release_dir}/${RELEASE_NAME}.tar.gz" "${MOD_NAME}" && \
    zip -r "${release_dir}/${RELEASE_NAME}.zip" "${MOD_NAME}" )

  cd "${release_dir}" && {
    md5sum "${RELEASE_NAME}.tar.gz" >> checksum.txt
    md5sum "${RELEASE_NAME}.zip" >> checksum.txt
    cd "${repo_root}"
  }
}

function install_release() {
  if [ "${MOD_STAGE}" == "local" ]; then
    # Install directly into ~/Zomboid/mods/ so PZ discovers it without a Workshop wrapper
    mkdir -p ~/Zomboid/mods
    cp -r "${RELEASE_DIR_MOD_HOME}" ~/Zomboid/mods/"${MOD_NAME}"
  else
    mkdir -p ~/Zomboid/Workshop
    cp -r .tmp/release/"${RELEASE_NAME}" ~/Zomboid/Workshop/"${MOD_NAME}"
  fi
  rm -r .tmp/release/"${RELEASE_NAME}"
}

remove_old_release && \
  create_folders && \
  make_release && \
  compress_release && \
  install_release
