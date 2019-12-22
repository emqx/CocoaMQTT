#!/bin/bash

source xcenv.sh
declare -r DIR_BUILD="${OBJECT_FILE_DIR_normal}/${CURRENT_ARCH}/"
xcode-coveralls "${DIR_BUILD}"
