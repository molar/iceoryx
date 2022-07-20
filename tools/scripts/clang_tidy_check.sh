#!/bin/bash

# Copyright (c) 2022 by Apex.AI Inc. All rights reserved.
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
#
# SPDX-License-Identifier: Apache-2.0

# This script checks code files with clang-tidy
# Example usage: ./tools/scripts/clang_tidy_check.sh full|hook|ci_pull_request

set -e

MODE=${1:-full} # Can be either `full` for all files or `hook` for formatting with git hooks

FILE_FILTER="\.(h|hpp|inl|c|cpp)$"

fail() {
    printf "\033[1;31merror: %s: %s\033[0m\n" ${FUNCNAME[1]} "${1:-"Unknown error"}"
    exit 1
}

CLANG_TIDY_VERSION=15
CLANG_TIDY_CMD="clang-tidy-$CLANG_TIDY_VERSION"
if ! command -v $CLANG_TIDY_CMD &> /dev/null
then
    CLANG_TIDY_MAJOR_VERSION=$(clang-tidy --version | sed -rn 's/.*([0-9][0-9])\.[0-9].*/\1/p')
    if [[ $CLANG_TIDY_MAJOR_VERSION -lt "$CLANG_TIDY_VERSION" ]]; then
        echo "Warning: clang-tidy version $CLANG_TIDY_VERSION or higher is not installed."
        echo "This may cause undetected warnings or that warnings suppressed by NOLINTBEGIN/NOLINTEND will not be suppressed."
    fi
    CLANG_TIDY_CMD="clang-tidy"
fi


WORKSPACE=$(git rev-parse --show-toplevel)
cd "${WORKSPACE}"

if ! [[ -f build/compile_commands.json ]]; then
    export CXX=clang++
    export CC=clang
    cmake -Bbuild -Hiceoryx_meta -DBUILD_ALL=ON
fi

echo "Using clang-tidy version: $($CLANG_TIDY_CMD --version | sed -n "s/.*version \([0-9.]*\)/\1/p" )"

noSpaceInSuppressions=$(git ls-files | grep -E "$FILE_FILTER" | xargs -I {} grep -h '// NOLINTNEXTLINE (' {} || true)
if [[ -n "$noSpaceInSuppressions" ]]; then
    echo -e "\e[1;31mRemove space between NOLINTNEXTLINE and '('!\e[m"
    echo "$noSpaceInSuppressions"
    exit 1
fi

if [[ "$MODE" == "hook"* ]]; then
    FILES=$(git diff --cached --name-only --diff-filter=CMRT | grep -E "$FILE_FILTER" | cat)
    # List only added files
    ADDED_FILES=$(git diff --cached --name-only --diff-filter=A | grep -E "$FILE_FILTER" | cat)
    echo "Checking files with Clang-Tidy"
    echo " "
        if [ -z "$FILES" ]; then
              echo "No modified files to check, skipping clang-tidy"
        else
            $CLANG_TIDY_CMD -p build $FILES
        fi

        if [ -z "$ADDED_FILES" ]; then
            echo "No added files to check, skipping clang-tidy"
        else
            $CLANG_TIDY_CMD --warnings-as-errors=* -p build $ADDED_FILES
        fi
    exit
elif [[ "$MODE" == "full"* ]]; then
    DIRECTORY_TO_SCAN=$2

    if [[ -n $DIRECTORY_TO_SCAN ]]
    then
        if ! test -d "$DIRECTORY_TO_SCAN"
        then
            echo "The directory which should be scanned '${DIRECTORY_TO_SCAN}' does not exist"
            exit 1
        fi

        echo "scanning all files in '${DIRECTORY_TO_SCAN}'"
        $CLANG_TIDY_CMD -p build $(find $DIRECTORY_TO_SCAN -type f | grep -E $FILE_FILTER )
        exit $?
    else
        FILES=$(git ls-files | grep -E "$FILE_FILTER")
        echo "Checking all files with Clang-Tidy"
        echo " "
        echo $FILES
        $CLANG_TIDY_CMD -p build $FILES
        exit $?
    fi
elif [[ "$MODE" == "scan_list"* ]]; then
    FILE_WITH_SCAN_LIST=$2
    FILE_TO_SCAN=$3

    if ! test -f "$FILE_WITH_SCAN_LIST"
    then
        echo "Scan list file '${FILE_WITH_SCAN_LIST}' does not exist"
        exit 1
    fi

    for LINE in $(cat $FILE_WITH_SCAN_LIST); do
        # add files until the comment section starts
        if [[ "$(echo $LINE | grep "#" | wc -l)" == "1" ]]; then
            break
        fi
        FILE_LIST="${FILE_LIST} $LINE"
    done

    if [[ -n $FILE_TO_SCAN ]]
    then
        if ! test -f "$FILE_TO_SCAN"
        then
            echo "The file which should be scanned '${FILE_TO_SCAN}' does not exist"
            exit 1
        fi

        if [[ $(find ${FILE_LIST} -type f | grep -E ${FILE_FILTER} | grep ${FILE_TO_SCAN} | wc -l) == "0" ]]
        then
            echo "Skipping file '${FILE_TO_SCAN}' since it is not part of '${FILE_WITH_SCAN_LIST}'"
            exit 0
        fi

        echo "Scanning file: ${FILE_TO_SCAN}"
        $CLANG_TIDY_CMD --warnings-as-errors=* -p build $FILE_TO_SCAN
    else
        if [[ -z $FILE_LIST ]]
        then
            echo "'${FILE_WITH_SCAN_LIST}' is empty skipping folder scan."
            exit 0
        fi
        echo "Performing full scan of all folders in '${FILE_WITH_SCAN_LIST}'"
        $CLANG_TIDY_CMD --warnings-as-errors=* -p build $(find ${FILE_LIST} -type f | grep -E ${FILE_FILTER})
    fi
    exit $?
else
    echo "Invalid mode: ${MODE}"
    exit 1
fi
