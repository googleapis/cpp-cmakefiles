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

# Compile projects that utilize the cpp-cmakefiles header files and libraries
# installed to the system. This script expects that the entire source tree is
# copied to /home/build/cpp-cmakefiles. Don't try to run this locally.

set -eu

# Verify the installed CMake config and pkgconfig files are actually usable.

for subdir in bigquery bigtable pubsub spanner; do
  # Compile a test program using CMake.
  echo "================================================================"
  echo "Testing ${subdir} $(date) with CMake"
  echo "================================================================"
  src_dir="/home/build/cpp-cmakefiles/ci/test-install/${subdir}"
  cmake_dir="/home/build/test-cmake-${subdir}"
  make_dir="/home/build/test-make-${subdir}"
  cmake -H"${src_dir}" -B"${cmake_dir}"
  cmake --build "${cmake_dir}" -- -j "$(nproc)"
  # Verify the generated program is runnable
  "${cmake_dir}/utilize-googleapis"
  echo "================================================================"
  echo "Testing ${subdir} $(date) with Make"
  echo "================================================================"
  cp -R "${src_dir}" "${make_dir}"
  cd "${make_dir}"
  # With Make we may need to set PKG_CONFIG_PATH because the code is installed
  # in /usr/local and that is not a default search location in some distros.
  env PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig \
        make
  # Verify the generated program is runnable
  "${make_dir}/main"
done
