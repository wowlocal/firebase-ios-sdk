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

# We will be working with relative paths
cd `dirname $0`

# Generate dylib for each file from dylib_stubs directory
find dylib_stubs -iname "*.c" | while read path_to_file
do
	# generate via cocoapods?
	clang "$path_to_file" -dynamiclib -o "${path_to_file%.*}".dylib -arch x86_64
done
