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

# For bigtable protos
cp -R /home/build/cpp-cmakefiles/ci/test-install/bigtable \
  /home/build/test-install-bigtable
cd /home/build/test-install-bigtable
cmake -H. -Bcmake-out
cmake --build cmake-out -- -j "$(nproc)"
cmake-out/utilize-googleapis

# For spanner protos
cp -R /home/build/cpp-cmakefiles/ci/test-install/spanner \
  /home/build/test-install-spanner
cd /home/build/test-install-spanner
cmake -H. -Bcmake-out
cmake --build cmake-out -- -j "$(nproc)"
cmake-out/utilize-googleapis
