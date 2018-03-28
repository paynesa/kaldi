#!/bin/bash -u

# Copyright 2012  Arnab Ghoshal

#
# Copyright 2016 by Idiap Research Institute, http://www.idiap.ch
#
# See the file COPYING for the licence associated with this software.
#
# Author(s):
#   Bogdan Vlasenko, February 2016
#   Enno Hermann, December 2017


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

# This script shows the steps needed to train monolingual systems for different
# languages of the GlobalPhone corpus.
echo "This shell script may run as-is on your system, but it is recommended
that you run the commands one by one by copying and pasting into the shell."
#exit 1;

[ -f cmd.sh ] && source ./cmd.sh || echo "cmd.sh not found. Jobs may not execute properly."

# CHECKING FOR AND INSTALLING REQUIRED TOOLS:
#  This recipe requires shorten (3.6.1) and sox (14.3.2).
#  If they are not found, the local/gp_install.sh script will install them.
#local/gp_check_tools.sh $PWD path.sh || exit 1;

. path.sh || { echo "Cannot source path.sh"; exit 1; }

# Set the languages that will actually be processed
export GP_LANGUAGES="CZ FR GE PL PO RU"

# Feature suffix for DNN training.
feat_suffix=_mfcc_hires

# Check data is prepared.
for L in $GP_LANGUAGES; do
    for x in train dev eval; do
        utils/validate_data_dir.sh --no-feats data/$L/$x
    done
done

# Make MFCC features.
if [ $stage -le 1 ]; then
    for L in $GP_LANGUAGES; do
        # Only if features haven't been created already.
        if [ ! -f data/$L/train_mfcc/feats.scp ]; then
            ./make_feats.sh $L mfcc
        fi
    done
    wait;
fi

# Train monophone model.
if [ $stage -le 2 ]; then
    for L in $GP_LANGUAGES; do
        mkdir -p exp/$L/mono;
        steps/train_mono.sh --nj 10 --cmd "$train_cmd" \
                            data/$L/train_mfcc data/$L/lang exp/$L/mono >& exp/$L/mono/train.log &
    done
    wait;
fi

# Train tri1, which is first triphone pass
if [ $stage -le 3 ]; then
    for L in $GP_LANGUAGES; do
        (
            mkdir -p exp/$L/mono_ali
            steps/align_si.sh --nj 10 --cmd "$train_cmd" \
	                      data/$L/train_mfcc data/$L/lang exp/$L/mono exp/$L/mono_ali >& exp/$L/mono_ali/align.log

            num_states=$(grep "^$L" conf/tri.conf | cut -f2)
            num_gauss=$(grep "^$L" conf/tri.conf | cut -f3)
            mkdir -p exp/$L/tri1
            steps/train_deltas.sh --cmd "$train_cmd" \
	                          --cluster-thresh 100 $num_states $num_gauss data/$L/train_mfcc data/$L/lang \
	                          exp/$L/mono_ali exp/$L/tri1 >& exp/$L/tri1/train.log
        ) &
    done
    wait;
fi

# Align training set.
if [ $stage -le 4 ]; then
    for L in $GP_LANGUAGES; do
        (
            mkdir -p exp/$L/tri1_ali
            steps/align_si.sh --nj 10 --cmd "$train_cmd" \
                              data/$L/train_mfcc data/$L/lang exp/$L/tri1 exp/$L/tri1_ali \
	                      >& exp/$L/tri1_ali/tri1_ali.log

            ./steps/get_train_ctm.sh data/$L/train_mfcc data/$L/lang exp/$L/tri1_ali  # written to exp/$L/tri1_ali/ctm
            ali-to-phones --ctm-output exp/$L/tri1/final.mdl \
                          ark:"gunzip -c exp/$L/tri1_ali/ali.*.gz|" - | \
                utils/int2sym.pl -f 5 data/$L/lang/phones.txt > exp/$L/tri1_ali/phone.ctm
        ) &
    done
    wait;
fi

# Align dev and eval sets.
if [ $stage -le 5 ]; then
    for L in $GP_LANGUAGES; do
        for set in "eval" "dev"; do
            mkdir -p exp/$L/tri1_${set}_ali
            steps/align_si.sh --nj 6 --cmd "$train_cmd" \
                              data/$L/${set}_mfcc data/$L/lang exp/$L/tri1 exp/$L/tri1_${set}_ali \
                              >& exp/$L/tri1_${set}_ali/align.log

            ./steps/get_train_ctm.sh data/$L/${set}_mfcc/ data/$L/lang exp/$L/tri1_${set}_ali
            ali-to-phones --ctm-output exp/$L/tri1/final.mdl \
                          ark:"gunzip -c exp/$L/tri1_${set}_ali/ali.*.gz|" - | \
                utils/int2sym.pl -f 5 data/$L/lang/phones.txt > exp/$L/tri1_${set}_ali/phone.ctm
        done
    done
fi

# Export alignment files.
if [ $stage -le 6 ]; then
    for L in $GP_LANGUAGES; do
        mkdir $ALIGN_DIR/$L

        mv exp/$L/tri1_ali/ctm $ALIGN_DIR/$L/train.ctm
        mv exp/$L/tri1_ali/phone.ctm $ALIGN_DIR/$L/train.phone.ctm

        for set in "eval" "dev"; do
            mv exp/$L/tri1_${set}_ali/ctm $ALIGN_DIR/$L/$set.ctm
            mv exp/$L/tri1_${set}_ali/phone.ctm $ALIGN_DIR/$L/$set.phone.ctm
        done
    done
fi

# Train tri2 (LDA+MLLT)
if [ $stage -le 7 ]; then
    for L in $GP_LANGUAGES; do
        (
            num_states=$(grep "^$L" conf/tri.conf | cut -f2)
            num_gauss=$(grep "^$L" conf/tri.conf | cut -f3)
            mkdir -p exp/$L/tri2
            steps/train_lda_mllt.sh --cmd "$train_cmd" \
  			            --splice-opts "--left-context=3 --right-context=3" \
  			            $num_states $num_gauss data/$L/train_mfcc data/$L/lang \
  			            exp/$L/tri1_ali \
  			            exp/$L/tri2 >& exp/$L/tri2/tri2.log
        ) &
    done
    wait;
fi

# Train tri3 (LDA+MLLT+SAT)
if [ $stage -le 8 ]; then
    for L in $GP_LANGUAGES; do
        (
            mkdir -p exp/$L/tri2_ali
            steps/align_fmllr.sh --nj 10 --cmd "$train_cmd" --use-graphs true \
			         data/$L/train_mfcc data/$L/lang exp/$L/tri2 exp/$L/tri2_ali >& exp/$L/tri2_ali/align.log
            wait;

            num_states=$(grep "^$L" conf/tri.conf | cut -f2)
            num_gauss=$(grep "^$L" conf/tri.conf | cut -f3)
            mkdir -p exp/$L/tri3
            steps/train_sat.sh --cmd "$train_cmd" \
  			       $num_states $num_gauss data/$L/train_mfcc data/$L/lang \
  			       exp/$L/tri2_ali \
  			       exp/$L/tri3 >& exp/$L/tri3/tri3.log
        ) &
    done
    wait;
fi

# Align tri3
if [ $stage -le 9 ]; then
    for L in $GP_LANGUAGES; do
        (
        mkdir -p exp/$L/tri3_ali
        steps/align_fmllr.sh --nj 10 --cmd "$train_cmd" --use-graphs true \
			     data/$L/train_mfcc data/$L/lang exp/$L/tri3 \
			     exp/$L/tri3_ali >& exp/$L/tri3_ali/align.log
        ) &
    done
    wait;
fi

# Make high resolution MFCCs for multilingual training
if [ $stage -le 10 ]; then
    for L in $GP_LANGUAGES; do
        for x in train dev eval; do
            (
                utils/copy_data_dir.sh data/$L/${x}_mfcc data/$L/${x}_mfcc_hires
                steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf \
                                   --cmd "$train_cmd" data/$L/${x}_mfcc_hires \
                                   exp/$L/make_hires/${x} feats/mfcc_hires/$L
                steps/compute_cmvn_stats.sh data/$L/${x}_mfcc_hires \
                                            exp/$L/make_hires/${x} feats/mfcc_hires/$L
            ) &
        done
    done
    wait;
fi

# Train sgmm2, which is SGMM on top of LDA+MLLT+SAT features.
if [ $stage -le 11 ]; then
    for L in $GP_LANGUAGES; do
        (
            num_states=$(grep "^$L" conf/sgmm.conf | cut -f2)
            num_substates=$(grep "^$L" conf/sgmm.conf | cut -f3)
            mkdir -p exp/$L/ubm4a
            steps/train_ubm.sh --cmd "$train_cmd" \
                               600 data/$L/train_mfcc data/$L/lang exp/$L/tri3_ali exp/$L/ubm4a

            mkdir -p exp/$L/sgmm2_4a
            steps/train_sgmm2.sh --cmd "$train_cmd" \
                                 $num_states $num_substates data/$L/train_mfcc data/$L/lang \
                                 exp/$L/tri3_ali exp/$L/ubm4a/final.ubm exp/$L/sgmm2_4a
        ) &
    done
    wait;
fi

# Align sgmm2
if [ $stage -le 12 ]; then
    for L in $GP_LANGUAGES; do
        (
            mkdir -p exp/$L/sgmm2_4a_ali
            steps/align_sgmm2.sh --nj 10 --cmd "$train_cmd" \
                                 --transform-dir exp/$L/tri3_ali --use-graphs true \
                                 --use-gselect true data/$L/train_mfcc \
                                 data/$L/lang exp/$L/sgmm2_4a exp/$L/sgmm2_4a_ali
        ) &
    done
    wait;
fi

# Train discriminative SGMM2+MMI system (don't need this for alignments).
# if [ $stage -le 12 ]; then
#     for L in $GP_LANGUAGES; do
#         (
#             mkdir -p exp/$L/sgmm2_4a_denlats
#             steps/make_denlats_sgmm2.sh --nj 10 --sub-split 10 --cmd "$decode_cmd" \
#                                         --transform-dir exp/$L/tri3_ali data/$L/train_mfcc \
#                                         data/$L/lang exp/$L/sgmm2_4a_ali exp/$L/sgmm2_4a_denlats
#             mkdir -p exp/$L/sgmm2_4a_mmi_b0.1
#             steps/train_mmi_sgmm2.sh --cmd "$decode_cmd" \
#                                      --transform-dir exp/$L/tri3_ali --boost 0.1 \
#                                      data/$L/train_mfcc data/$L/lang exp/$L/sgmm2_4a_ali \
#                                      exp/$L/sgmm2_4a_denlats exp/$L/sgmm2_4a_mmi_b0.1
#         ) &
#     done
#     wait;
# fi
