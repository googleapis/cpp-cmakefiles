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

export CC=gcc
export CXX=g++
export DISTRO=ubuntu
export DISTRO_VERSION=18.04
export CMAKE_SOURCE_DIR="."

in_docker_script="ci/kokoro/docker/build-in-docker-cmake.sh"

if [[ $# -eq 1 ]]; then
  export BUILD_NAME="${1}"
elif [[ -n "${KOKORO_JOB_NAME:-}" ]]; then
  # Kokoro injects the KOKORO_JOB_NAME environment variable, the value of this
  # variable is cloud-cpp/spanner/<config-file-name-without-cfg> (or more
  # generally <path/to/config-file-without-cfg>). By convention we name these
  # files `$foo.cfg` for continuous builds and `$foo-presubmit.cfg` for
  # presubmit builds. Here we extract the value of "foo" and use it as the build
  # name.
  BUILD_NAME="$(basename "${KOKORO_JOB_NAME}" "-presubmit")"
  export BUILD_NAME
else
  echo "Aborting build as the build name is not defined."
  echo "If you are invoking this script via the command line use:"
  echo "    $0 <build-name>"
  echo
  echo "If this script is invoked by Kokoro, the CI system is expected to set"
  echo "the KOKORO_JOB_NAME environment variable."
  exit 1
fi

if [[ "${BUILD_NAME}" = "clang-tidy" ]]; then
  # Compile with clang-tidy(1) turned on. The build treats clang-tidy warnings
  # as errors.
  export DISTRO=fedora
  export DISTRO_VERSION=30
  export CC=clang
  export CXX=clang++
  export CHECK_STYLE=yes
  export CLANG_TIDY=yes
elif [[ "${BUILD_NAME}" = "ubuntu-18.04" ]]; then
  export CC=gcc
  export CXX=g++
elif [[ "${BUILD_NAME}" = "ubuntu-16.04" ]]; then
  export DISTRO_VERSION=16.04
  export CC=gcc
  export CXX=g++
elif [[ "${BUILD_NAME}" = "gcc-4.8" ]]; then
  # The oldest version of GCC we support is 4.8, this build checks the code
  # against that version. The use of CentOS 7 for that build is not a
  # coincidence: the reason we support GCC 4.8 is to support this distribution
  # (and its commercial cousin: RHEL 7).
  export CC=gcc
  export CXX=g++
  export DISTRO=centos
  export DISTRO_VERSION=7
elif [[ "${BUILD_NAME}" = "clang-3.8" ]]; then
  # The oldest version of Clang we actively test is 3.8. There is nothing
  # particularly interesting about that version. It is simply the version
  # included with Ubuntu:16.04, and the oldest version tested by
  # google-cloud-cpp.
  export DISTRO=ubuntu
  export DISTRO_VERSION=16.04
  export CC=clang
  export CXX=clang++
elif [[ "${BUILD_NAME}" = "ninja" ]]; then
  # Compiling with Ninja can catch bugs that may not be caught using Make.
  export USE_NINJA=yes
else
  echo "Unknown BUILD_NAME (${BUILD_NAME}). Fix the Kokoro .cfg file."
  exit 1
fi

if [[ -z "${PROJECT_ROOT+x}" ]]; then
  readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../../.."; pwd)"
fi

if [[ -z "${PROJECT_ID+x}" ]]; then
  readonly PROJECT_ID="cloud-devrel-kokoro-resources"
fi

# Determine the image name.
readonly IMAGE="gcr.io/${PROJECT_ID}/cpp-cmakefiles/${DISTRO}-${DISTRO_VERSION}"
readonly BUILD_OUTPUT="cmake-out/${BUILD_NAME}"
readonly BUILD_HOME="cmake-out/home/${BUILD_NAME}"

echo "================================================================"
cd "${PROJECT_ROOT}"
echo "Building with $(nproc) cores $(date) on ${PWD}."

echo "================================================================"
echo "Capture Docker version to troubleshoot $(date)."
docker version
echo "================================================================"

has_cache="false"

if [[ -n "${KOKORO_JOB_NAME:-}" ]]; then
  # Download the docker image from the previous build on kokoro for speed.
  echo "================================================================"
  echo "Downloading Docker image $(date)."
  gcloud auth configure-docker
  if docker pull "${IMAGE}:latest"; then
    echo "Existing image successfully downloaded."
    has_cache="true"
  fi
  echo "================================================================"
fi

docker_build_flags=(
  "-t" "${IMAGE}:latest"
)

if [[ -f "ci/kokoro/Dockerfile.${DISTRO}-${DISTRO_VERSION}" ]]; then
  docker_build_flags+=("-f" "ci/kokoro/Dockerfile.${DISTRO}-${DISTRO_VERSION}")
else
  docker_build_flags+=(
    "-f" "ci/kokoro/Dockerfile.${DISTRO}"
    "--build-arg" "DISTRO_VERSION=${DISTRO_VERSION}"
  )
fi

if "${has_cache}"; then
  docker_build_flags+=("--cache-from=${IMAGE}:latest")
fi

update_cache="false"
echo "================================================================"
echo "Creating Docker image with all the development tools $(date)."
if ci/retry-command.sh docker build "${docker_build_flags[@]}" ci; then
  update_cache="true"
  echo "Docker image created $(date)."
  docker image ls | grep "${IMAGE}"
else
  echo "Failed creating Docker image $(date)."
  if "${has_cache}"; then
    echo "Continue the build with the cache."
  else
    exit 1   
  fi
fi
echo "================================================================"

if [[ -n "${KOKORO_JOB_NAME:-}" ]]; then
  # Upload the docker image for speeding up the future builds.
  echo "================================================================"
  echo "Uploading Docker image $(date)."
  docker push "${IMAGE}:latest" || true
  echo "================================================================"
fi


echo "================================================================"
echo "Running the full build $(date)."
# The default user for a Docker container has uid 0 (root). To avoid creating
# root-owned files in the build directory we tell docker to use the current
# user ID, if known.
docker_uid="${UID:-0}"
docker_user="${USER:-root}"
docker_home_prefix="${PWD}/cmake-out/home"
if [[ "${docker_uid}" == "0" ]]; then
  docker_home_prefix="${PWD}/cmake-out/root"
fi

# Make sure the user has a $HOME directory inside the Docker container.
mkdir -p "${BUILD_HOME}"
mkdir -p "${BUILD_OUTPUT}"

# We use an array for the flags so they are easier to document.
docker_flags=(
    # Grant the PTRACE capability to the Docker container running the build,
    # this is needed by tools like AddressSanitizer.
    "--cap-add" "SYS_PTRACE"

    # The name and version of the distribution, this is used to call
    # define-docker-variables.sh and determine the Docker image built, and the
    # output directory for any artifacts.
    "--env" "DISTRO=${DISTRO}"
    "--env" "DISTRO_VERSION=${DISTRO_VERSION}"

    # The C++ and C compiler, both Bazel and CMake use this environment variable
    # to select the compiler binary.
    "--env" "CXX=${CXX}"
    "--env" "CC=${CC}"

    # If set to 'yes', the build script will run the style checks, including
    # clang-format, cmake-format, and buildifier.
    "--env" "CHECK_STYLE=${CHECK_STYLE:-}"

    # If set to 'yes', the build script will configure clang-tidy. Currently
    # only the CMake builds use this flag.
    "--env" "CLANG_TIDY=${CLANG_TIDY:-}"

    # If set to 'yes', run the integration tests. Currently only the Bazel
    # builds use this flag.
    "--env" "RUN_INTEGRATION_TESTS=${RUN_INTEGRATION_TESTS:-}"

    # If set to 'yes', run compile with code coverage flags. Currently only the
    # CMake builds use this flag.
    "--env" "CODE_COVERAGE=${CODE_COVERAGE:-}"

    # If set to 'yes', use Ninja as the CMake generator. Ninja is more strict
    # that Make and can detect errors in your CMake files, it is also faster.
    "--env" "USE_NINJA=${USE_NINJA:-}"

    # If set, pass -DGOOGLE_CLOUD_CPP_CXX_STANDARD=<value> to CMake.
    "--env" "GOOGLE_CLOUD_CPP_CXX_STANDARD=${GOOGLE_CLOUD_CPP_CXX_STANDARD:-}"

    # When running the integration tests this directory contains the
    # configuration files needed to run said tests. Make it available inside
    # the Docker container.
    "--volume" "${KOKORO_GFILE_DIR:-/dev/shm}:/c"

    # Let the Docker image script know what kind of terminal we are using, that
    # produces properly colorized error messages.
    "--env" "TERM=${TERM:-dumb}"

    # Run the docker script and this user id. Because the docker image gets to
    # write in ${PWD} you typically want this to be your user id.
    "--user" "${docker_uid}"

    # Bazel needs this environment variable to work correctly.
    "--env" "USER=${docker_user}"

    # We give Bazel and CMake a fake $HOME inside the docker image. Bazel caches
    # build byproducts in this directory. CMake (when ccache is enabled) uses
    # it to store $HOME/.ccache
    "--env" "HOME=/h"
    "--volume" "${PWD}/${BUILD_HOME}:/h"

    # Mount the current directory (which is the top-level directory for the
    # project) as `/v` inside the docker image, and move to that directory.
    "--volume" "${PWD}:/v"
    "--workdir" "/v"

    # Mask any other builds that may exist at the same time. That is, these
    # directories appear as empty inside the Docker container, this prevents the
    # container from writing into other builds, or to get confused by the output
    # of other builds. In the CI system this does not matter, as each build runs
    # on a completely separate VM. This is useful when running multiple builds
    # in your workstation.
    "--volume" "/v/cmake-out/home"
    "--volume" "/v/cmake-out"
    "--volume" "${PWD}/${BUILD_OUTPUT}:/v/${BUILD_OUTPUT}"
)

# When running the builds from the command-line they get a tty, and the scripts
# running inside the Docker container can produce nicer output. On Kokoro the
# script does not get a tty, and Docker terminates the program if we pass the
# `-it` flag.
if [[ -t 0 ]]; then
  docker_flags+=("-it")
fi

docker run "${docker_flags[@]}" "${IMAGE}:latest" \
    "/v/${in_docker_script}" "${CMAKE_SOURCE_DIR}" \
    "${BUILD_OUTPUT}"
