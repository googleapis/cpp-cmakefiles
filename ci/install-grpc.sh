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

mkdir -p /var/tmp/Downloads
cd /var/tmp/Downloads

# Install protobuf
wget -q https://github.com/google/protobuf/archive/v3.8.0.tar.gz
tar -xf v3.8.0.tar.gz
(cd protobuf-3.8.0/cmake;
 cmake \
   -DCMAKE_BUILD_TYPE=Release \
   -DBUILD_SHARED_LIBS=yes \
   -Dprotobuf_BUILD_TESTS=OFF \
   -H. -Bcmake-out
 cmake --build cmake-out --target install -- -j "$(nproc)"
 ldconfig
)

# Install grpc
wget -q https://github.com/grpc/grpc/archive/v1.22.0.tar.gz
tar -xf v1.22.0.tar.gz
(cd grpc-1.22.0;
 make -j "$(nproc)"
 make install
 ldconfig
)
