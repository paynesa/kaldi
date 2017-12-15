#!/bin/bash -u

# See the file COPYING for the licence associated with this software.
#
# Author(s):
#   Enno Hermann, October 2017
#

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

GP_LANGUAGES=$1
feats=$2  # 'mfcc', 'plp', or 'fbank'

# This script shows the steps needed to create acoustic features for certain
# languages of the GlobalPhone corpus.
echo "This shell script may run as-is on your system, but it is recommended
that you run the commands one by one by copying and pasting into the shell."
#exit 1;

[ -f cmd.sh ] && source ./cmd.sh || echo "cmd.sh not found. Jobs may not execute properly."

. path.sh || { echo "Cannot source path.sh"; exit 1; }

# Copy over data files.
for L in $GP_LANGUAGES; do
    for x in train dev eval; do
        copy_data_dir.sh data/$L/${x} data/$L/${x}_$feats
    done
done

# Now generate features.
for L in $GP_LANGUAGES; do
    featsdir=feats/$feats/$L
    rm -rdf $featsdir exp/$L/make_feats
    for x in train dev eval; do
        data=data/$L/${x}_$feats
        (
            steps/make_${feats}.sh --nj 6 --cmd "$train_cmd" $data \
                       exp/$L/make_feats/$x $featsdir;
            steps/compute_cmvn_stats.sh $data exp/$L/make_feats/$x $featsdir;
        ) &
    done
done
