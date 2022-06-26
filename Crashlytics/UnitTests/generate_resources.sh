#!/bin/bash

# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

sdk_name=(    "MacOSX" "MacOSX" "AppleTVSimulator" "iPhoneSimulator" )
target_name=( "macos"  "macos"  "tvos"             "ios" )
arch=(        "arm64"  "x86_64" "arm64"            "arm64" )
version=(     "10.15"  "10.15"  "10.0"             "9.0" )
simulator=(   false    false    true               true )

function target() {
	local retVal="${arch[$1]}-apple-${target_name[$1]}${version[$1]}"
	if [ ${simulator[$1]} == true ]; then
		retVal="$retVal-simulator"
	fi
	echo $retVal
}

function sdk_path() {
	echo "$(xcode-select -p)/Platforms/${sdk_name[$1]}.platform/Developer/SDKs/${sdk_name[$1]}.sdk"
}

# We will be working with relative paths
cd `dirname $0`

cd dylib_stubs
mkdir -p build
cd build

# Generate dylib for each file from dylib_stubs directory
find .. -iname "*.c" | while read path_to_file
do
	for i in {0..3}; do
		out_dir="${target_name[$i]}_${arch[$i]}"
		mkdir -p $out_dir && cd $out_dir
		filename=`basename $path_to_file`

		clang "../$path_to_file" -dynamiclib -o "${filename%.*}".dylib -target $(target $i) -isysroot $(sdk_path $i)

		cd ..
	done
done

ln -s ios_arm64 ios
ln -s tvos_arm64 tvos

mkdir macos
find macos_arm64 -iname "*.dylib" | while read arm64_dylib_path
do
	dylib_name=`basename $arm64_dylib_path`
	x86_64_dylib_path=`find macos_x86_64 -name "$dylib_name"`
	lipo -create "$arm64_dylib_path" "$x86_64_dylib_path" -output "macos/$dylib_name"
done