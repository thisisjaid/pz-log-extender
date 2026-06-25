#!/usr/bin/env bash

# release.sh prepares mod files from src to Zomboid/Workshop folder.
#
# Copyright (c) 2023 Pavel Korotkiy (outdead).
# Use of this source code is governed by the MIT license.
#
# Usage: ./release.sh <version> [stage] [build]
#   version  Semantic version, e.g. 0.14.0
#   stage    prod (default) | test | local
#   build    b41 (default)  | b42
#
# Examples:
#   ./release.sh 0.13.0              # B41 prod release
#   ./release.sh 0.14.0 prod b42     # B42 prod release
#   ./release.sh 0.14.0 test b42     # B42 test release

# MOD_VERSION of current mod.
# Follows semantic versioning, SEE: http://semver.org/.
MOD_VERSION="$1"
if [ -z "${MOD_VERSION}" ]; then echo "MOD_VERSION is not set. Use ./release.sh 0.0.0 [stage] [build]" >&2; exit 1; fi

MOD_STAGE="$2"
if [ -z "${MOD_STAGE}" ]; then MOD_STAGE="prod"; fi

MOD_BUILD="$3"
if [ -z "${MOD_BUILD}" ]; then MOD_BUILD="b41"; fi

case ${MOD_STAGE} in
  local|test|prod)
    ;;
  *)
    echo "[  ER  ] Incorrect stage \"${MOD_STAGE}\". Use: prod, test, local" >&2; exit 1 ;;
esac

case ${MOD_BUILD} in
  b41|b42)
    ;;
  *)
    echo "[  ER  ] Incorrect build \"${MOD_BUILD}\". Use: b41, b42" >&2; exit 1 ;;
esac

# B42 releases use a prefixed workshop directory and carry a build suffix in the archive name.
if [ "${MOD_BUILD}" == "b42" ]; then
  WORKSHOP_DIR="b42_${MOD_STAGE}"
  SRC_DIR="src/b42"
  VERSION_SUFFIX="-b42"
else
  WORKSHOP_DIR="${MOD_STAGE}"
  SRC_DIR="src/b41"
  VERSION_SUFFIX=""
fi

MOD_NAME="LogExtender"
if [ "${MOD_STAGE}" == "test" ]; then MOD_NAME="${MOD_NAME}Test"; fi
if [ "${MOD_STAGE}" == "local" ]; then MOD_NAME="${MOD_NAME}Local"; fi
if [ "${MOD_BUILD}" == "b42" ] && [ "${MOD_STAGE}" == "test" ]; then MOD_NAME="LogExtenderB42Test"; fi
if [ "${MOD_BUILD}" == "b42" ] && [ "${MOD_STAGE}" == "local" ]; then MOD_NAME="LogExtenderB42Test"; fi

echo "[ INFO ] Preparing ${MOD_NAME} release v${MOD_VERSION}${VERSION_SUFFIX} (build=${MOD_BUILD} stage=${MOD_STAGE})"

RELEASE_NAME="${MOD_NAME}-${MOD_VERSION}${VERSION_SUFFIX}"

RELEASE_DIR_WORKSHOP=".tmp/release/${RELEASE_NAME}"
if [ "${MOD_BUILD}" == "b42" ]; then
  RELEASE_DIR_MOD_HOME="${RELEASE_DIR_WORKSHOP}/mods/${MOD_NAME}"
else
  RELEASE_DIR_MOD_HOME="${RELEASE_DIR_WORKSHOP}/Contents/mods/${MOD_NAME}"
fi

function remove_old_release() {
  rm -rf .tmp/release
  rm -rf ~/Zomboid/Workshop/"${MOD_NAME}"
  if [ "${MOD_BUILD}" == "b42" ] && [ "${MOD_STAGE}" == "local" ]; then
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

  if [ "${MOD_BUILD}" == "b42" ]; then
    local dir_b42="${dir_mod_home}/42"
    mkdir -p "${dir_b42}"
  else
    mkdir -p "${dir_mod_home}"
  fi

  cp "workshop/${WORKSHOP_DIR}/workshop.txt" "${dir_workshop}"
  cp workshop/preview.png "${dir_workshop}/preview.png"

  if [ "${MOD_BUILD}" == "b42" ]; then
    local dir_b42="${dir_mod_home}/42"

    # Root: mod.info + poster for PZ mod discovery
    cp "workshop/${WORKSHOP_DIR}/mod.info" "${dir_mod_home}/mod.info"
    cp workshop/poster.png "${dir_mod_home}/poster.png"

    # 42/: version-scoped content — B41 will never load this directory
    cp "workshop/${WORKSHOP_DIR}/mod.info" "${dir_b42}/mod.info"
    cp workshop/poster.png "${dir_b42}/poster.png"
    cp -r "${SRC_DIR}" "${dir_b42}/media"
    cp LICENSE "${dir_b42}"
    cp README.md "${dir_b42}"
    cp CHANGELOG.md "${dir_b42}"
  else
    cp "workshop/${WORKSHOP_DIR}/mod.info" "${dir_mod_home}"
    cp workshop/poster.png "${dir_mod_home}"
    cp -r "${SRC_DIR}" "${dir_mod_home}/media"
    cp LICENSE "${dir_mod_home}"
    cp README.md "${dir_mod_home}"
    cp CHANGELOG.md "${dir_mod_home}"
  fi
}

function compress_release() {
  local repo_root
  repo_root="$(pwd)"
  local release_dir="${repo_root}/.tmp/release"
  local mod_parent

  if [ "${MOD_BUILD}" == "b42" ]; then
    mod_parent="${RELEASE_DIR_WORKSHOP}/mods"
  else
    mod_parent="${RELEASE_DIR_WORKSHOP}/Contents/mods"
  fi

  ( cd "${mod_parent}" && \
    tar -zcvf "${release_dir}/${RELEASE_NAME}.tar.gz" "${MOD_NAME}" && \
    zip -r "${release_dir}/${RELEASE_NAME}.zip" "${MOD_NAME}" )

  cd "${release_dir}" && {
    md5sum "${RELEASE_NAME}.tar.gz" >> checksum.txt
    md5sum "${RELEASE_NAME}.zip" >> checksum.txt
    cd "${repo_root}"
  }
}

function install_release() {
  if [ "${MOD_BUILD}" == "b42" ] && [ "${MOD_STAGE}" == "local" ]; then
    # B42 local: install the mod directly into ~/Zomboid/mods/ so PZ finds it
    # without the Workshop wrapper layer
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
