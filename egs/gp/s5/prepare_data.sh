#!/bin/bash -u

# Copyright 2012  Arnab Ghoshal

#
# Copyright 2016 by Idiap Research Institute, http://www.idiap.ch
#
# See the file COPYING for the licence associated with this software.
#
# Author(s):
#   Bogdan Vlasenko, February 2016


# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# Set the languages that will be processed
export GP_LANGUAGES=$1

# This script prepares the data for different languages of the GlobalPhone corpus.
echo "This shell script may run as-is on your system, but it is recommended
that you run the commands one by one by copying and pasting into the shell."
#exit 1;

[ -f cmd.sh ] && source ./cmd.sh || echo "cmd.sh not found. Jobs may not execute properly."

# CHECKING FOR AND INSTALLING REQUIRED TOOLS:
#  This recipe requires shorten (3.6.1) and sox (14.3.2).
#  If they are not found, the local/gp_install.sh script will install them.
#local/gp_check_tools.sh $PWD path.sh || exit 1;

. path.sh || { echo "Cannot source path.sh"; exit 1; }

# Copy normalization scripts from Czech if they don't exist yet.
for L in $GP_LANGUAGES; do
    if [ ! -f local/gp_norm_trans_$L.pl ]; then
        cp local/gp_norm_trans_CZ.pl local/gp_norm_trans_$L.pl
    fi

    if [ ! -f local/gp_norm_dict_$L.pl ]; then
        cp local/gp_norm_dict_CZ.pl local/gp_norm_dict_$L.pl
    fi
done

# Data preparation
# The following data preparation step actually converts the audio files from
# shorten to WAV to take out the empty files and those with compression errors.
local/gp_data_prep.sh --config-dir=$PWD/conf --corpus-dir=$GP_CORPUS --languages="$GP_LANGUAGES" || exit 1;
local/gp_dict_prep.sh --config-dir $PWD/conf $GP_CORPUS $GP_LANGUAGES || exit 1;

for L in $GP_LANGUAGES; do
    utils/prepare_lang.sh --position-dependent-phones true \
                          data/$L/local/dict "<unk>" data/$L/local/lang_tmp data/$L/lang \
                          >& data/$L/prepare_lang.log || exit 1;
done

# Convert the different available language models to FSTs, and create separate
# decoding configurations for each.
for L in $GP_LANGUAGES; do
    local/gp_format_lm.sh --filter-vocab-sri true $GP_LM $L &
done
