#!/usr/bin/env bash
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

if [[ "${CHECK_STYLE}" != "yes" ]]; then
  echo "Skipping code style check as it is disabled for this build."
  exit 0
fi

# This script assumes it is running the top-level google-cloud-cpp directory.

readonly BINDIR="$(dirname "$0")"

# Build paths to ignore in find(1) commands by reading .gitignore.
declare -a ignore=( -path ./.git )
if [[ -f .gitignore ]]; then
  while read -r line; do
    case "${line}" in
    [^#]*/*) ignore+=( -o -path "./$(expr "${line}" : '\(.*\)/')" ) ;;
    [^#]*)   ignore+=( -o -name "${line}" ) ;;
    esac
  done < .gitignore
fi

replace_original_if_changed() {
  if [[ $# != 2 ]]; then
    return 1
  fi

  local original="$1"
  local reformatted="$2"

  if cmp -s "${original}" "${reformatted}"; then
    rm -f "${reformatted}"
  else
    chmod --reference="${original}" "${reformatted}"
    mv -f "${reformatted}" "${original}"
  fi
}

# Apply cmake_format to all the CMake list files.
#     https://github.com/cheshirekow/cmake_format
find . \( "${ignore[@]}" \) -prune -o \
       \( -name 'CMakeLists.txt' -o -name '*.cmake' \) \
       -print0 |
  while IFS= read -r -d $'\0' file; do
    cmake-format "${file}" >"${file}.tmp"
    replace_original_if_changed "${file}" "${file}.tmp"
  done

# Apply buildifier to fix the BUILD and .bzl formatting rules.
#    https://github.com/bazelbuild/buildtools/tree/master/buildifier
find . \( "${ignore[@]}" \) -prune -o \
       \( -name BUILD -o -name '*.bzl' \) \
       -print0 |
  xargs -0 buildifier -mode=fix

# Apply shellcheck(1) to emit warnings for common scripting mistakes.
find . \( "${ignore[@]}" \) -prune -o \
       -iname '*.sh' -exec shellcheck \
         --exclude=SC1090 \
         --exclude=SC2034 \
         --exclude=SC2153 \
         --exclude=SC2181 \
       '{}' \;

# Report any differences created by running the formatting tools.
git diff --ignore-submodules=all --color --exit-code .
