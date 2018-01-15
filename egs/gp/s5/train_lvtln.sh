#!/bin/bash -u

# See the file COPYING for the licence associated with this software.
#
# Author(s):
#   Enno Hermann, October 2017

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

stage=$1
feats=$2  # 'mfcc' or 'plp'

# This script shows the steps needed to train LVTLN models for the GlobalPhone corpus.
# NB: For training the UBM and LVTLN models, scripts that don't require any alignments
# or previously trained models are used to be able to do VTLN in zero-resource
# applications. If this is not a constraint, you might want to use the regular
# scripts UBM/LVTLN scripts.
echo "This shell script may run as-is on your system, but it is recommended
that you run the commands one by one by copying and pasting into the shell."
#exit 1;

[ -f cmd.sh ] && source ./cmd.sh || echo "cmd.sh not found. Jobs may not execute properly."

. path.sh || { echo "Cannot source path.sh"; exit 1; }

# Set the locations of the GlobalPhone corpus and language models
GP_CORPUS=/group/corporapublic/global_phone/

# Set the languages that will actually be processed
export GP_LANGUAGES="SP"

# Compute energy-based VAD.
if [ "$stage" -le 0 ] && [ "$feats" == "mfcc" ]; then
    for L in $GP_LANGUAGES; do
        for x in train dev eval; do
            $KALDI_ROOT/egs/sre08/v1/sid/compute_vad_decision.sh data/$L/${x}_mfcc exp/$L/vad_log vad/$L
            mkdir data/$L/${x}_plp/
            cp data/$L/${x}_mfcc/vad.scp data/$L/${x}_plp/
        done
    done
fi

# Train diagonal UBM.
if [ "$stage" -le 1 ]; then
    for L in $GP_LANGUAGES; do
        $KALDI_ROOT/egs/sre08/v1/sid/train_diag_ubm.sh \
            --nj 16 --cmd "$train_cmd" \
            data/$L/train_$feats 1024 exp/$L/diag_ubm_$feats
    done
fi

# Train LVTLN model.
if [ "$stage" -le 2 ]; then
    for L in $GP_LANGUAGES; do
        $KALDI_ROOT/egs/lre/v1/lid/train_lvtln_model.sh \
            --nj 16 --cmd "$train_cmd" --base_feat_type "$feats" \
            data/$L/train_$feats exp/$L/diag_ubm_$feats exp/$L/vtln_$feats
    done
fi

# Compute VTLN warp factors.
if [ "$stage" -le 3 ]; then
    for L in $GP_LANGUAGES; do
        for x in dev eval; do
            $KALDI_ROOT/egs/lre/v1/lid/get_vtln_warps.sh --nj 4 --cmd "$train_cmd" \
                data/$L/${x}_$feats exp/$L/vtln_$feats exp/$L/vtln_$feats/$x
        done
    done
fi

# Generate VTLN adapted features.
if [ "$stage" -le 4 ]; then
    for L in $GP_LANGUAGES; do
        # Set up new data folders.
        for x in train dev eval; do
            data="data/$L/${x}_$feats"
            data_vtln="data/$L/${x}_${feats}_vtln"
            copy_data_dir.sh $data $data_vtln

            if [ $x == "train" ]; then
                cp exp/$L/vtln_$feats/final.warp $data_vtln/utt2warp
            else
                cp exp/$L/vtln_$feats/$x/utt2warp $data_vtln/
            fi
        done

        # Generate new features.
        featsdir=feats/${feats}_vtln/$L
        for x in train dev eval; do
            (
                data_vtln="data/$L/${x}_${feats}_vtln"
                steps/make_$feats.sh \
                    --nj 6 --cmd "$train_cmd" $data_vtln \
                    exp/$L/make_${feats}_vtln/$x $featsdir;
                steps/compute_cmvn_stats.sh \
                    $data_vtln exp/$L/make_$feats/$x $featsdir;
            ) &
        done
    done
fi
