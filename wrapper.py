#!/usr/bin/python

# Copyright (c) 2010 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
import os
import subprocess
import sys

# This python script wraps gcc-mp-4.X so it can handle
# compilation options memcheck uses on Mac, including:
#  a) skip "-arch XXX"
#  b) define empty "__private_extern__" macro so it doesn't bark
#     on mac-specific code using this keyword.
#  c) skip "-mno-dynamic-no-pic" and "-mdynamic-no-pic"
#     This may not be a very clean solution in general but it works.

# The gcc command should be passes as an environment variable,
# e.g. GCC_BINARY_MASK=/opt/local/bin/XXX-mp-4.4
assert os.environ.has_key("GCC_BINARY_MASK")
gcc_binary_mask = os.environ["GCC_BINARY_MASK"]
gcc = gcc_binary_mask.replace("XXX", sys.argv[1])

gcc_command = [gcc, "-D__private_extern__="]
skip = 0
for arg in sys.argv[2:]:
  if skip > 0:
    skip -= 1
    continue
  if arg == "-arch":
    skip = 1
    continue
  if arg == "-mno-dynamic-no-pic":
    continue
  if arg == "-mdynamic-no-pic":
    continue
  gcc_command.append(arg)

subprocess.call(gcc_command)
