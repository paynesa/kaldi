#!/bin/bash -u

# See the file COPYING for the licence associated with this software.
#
# Author(s):
#   Enno Hermann, January 2018


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

# This script shows the steps needed to decode monolingual systems for different
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
export GP_LANGUAGES="BG KO TH VN"

function count_spk {
    L=$1
    x=$2
    n_spk=$(grep $L conf/${x}_spk.list | cut -f 2 | wc -w)
    echo $n_spk
}

# Decode monophone model.
if [ $stage -le 0 ]; then
    for L in $GP_LANGUAGES; do
        if [ -f exp/$L/mono/final.mdl ]; then
            for lm_suffix in tgpr_sri; do
                (
                    graph_dir=exp/$L/mono/graph_${lm_suffix}
                    mkdir -p $graph_dir
                    utils/mkgraph.sh data/$L/lang_test_${lm_suffix} exp/$L/mono \
                                     $graph_dir

                    steps/decode.sh --nj $( count_spk $L dev ) --cmd "$decode_cmd" $graph_dir data/$L/dev_mfcc \
                                    exp/$L/mono/decode_dev_${lm_suffix}
                    grep WER exp/$L/mono/decode_dev_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                    steps/decode.sh --nj $( count_spk $L eval ) --cmd "$decode_cmd" $graph_dir data/$L/eval_mfcc \
                                    exp/$L/mono/decode_eval_${lm_suffix}
                    grep WER exp/$L/mono/decode_eval_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                ) &
            done
        fi
    done
    wait;
fi

# Decode tri1 model.
if [ $stage -le 1 ]; then
    for L in $GP_LANGUAGES; do
        if [ -f exp/$L/tri1/final.mdl ]; then
            for lm_suffix in tgpr_sri; do
                (
                    graph_dir=exp/$L/tri1/graph_${lm_suffix}
                    mkdir -p $graph_dir
                    utils/mkgraph.sh data/$L/lang_test_${lm_suffix} exp/$L/tri1 \
                                     $graph_dir

                    steps/decode.sh --nj $( count_spk $L dev ) --cmd "$decode_cmd" $graph_dir data/$L/dev_mfcc \
                                    exp/$L/tri1/decode_dev_${lm_suffix}
                    grep WER exp/$L/tri1/decode_dev_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                    steps/decode.sh --nj $( count_spk $L eval ) --cmd "$decode_cmd" $graph_dir data/$L/eval_mfcc \
                                    exp/$L/tri1/decode_eval_${lm_suffix}
                    grep WER exp/$L/tri1/decode_eval_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                ) &
            done
        fi
    done
    wait;
fi

# Decode tri2 model.
if [ $stage -le 2 ]; then
    for L in $GP_LANGUAGES; do
        if [ -f exp/$L/tri2/final.mdl ]; then
            for lm_suffix in tgpr_sri; do
                (
                    graph_dir=exp/$L/tri2/graph_${lm_suffix}
                    mkdir -p $graph_dir
                    utils/mkgraph.sh data/$L/lang_test_${lm_suffix} exp/$L/tri2 \
                                     $graph_dir

                    steps/decode.sh --nj $( count_spk $L dev ) --cmd "$decode_cmd" $graph_dir data/$L/dev_mfcc \
                                    exp/$L/tri2/decode_dev_${lm_suffix}
                    grep WER exp/$L/tri2/decode_dev_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                    steps/decode.sh --nj $( count_spk $L eval ) --cmd "$decode_cmd" $graph_dir data/$L/eval_mfcc \
                                    exp/$L/tri2/decode_eval_${lm_suffix}
                    grep WER exp/$L/tri2/decode_eval_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                ) &
            done
        fi
    done
    wait;
fi

# Decode tri3 model.
if [ $stage -le 3 ]; then
    for L in $GP_LANGUAGES; do
        if [ -f exp/$L/tri3/final.mdl ]; then
            for lm_suffix in tgpr_sri; do
                (
                    graph_dir=exp/$L/tri3/graph_${lm_suffix}
                    mkdir -p $graph_dir
                    utils/mkgraph.sh data/$L/lang_test_${lm_suffix} exp/$L/tri3 \
                                     $graph_dir

                    mkdir -p exp/$L/tri3/decode_dev_${lm_suffix}
                    steps/decode_fmllr.sh --nj $( count_spk $L dev ) --cmd "$decode_cmd" $graph_dir \
                                          data/$L/dev_mfcc exp/$L/tri3/decode_dev_${lm_suffix}
                    grep WER exp/$L/tri3/decode_dev_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                    steps/decode_fmllr.sh --nj $( count_spk $L eval ) --cmd "$decode_cmd" $graph_dir \
                                          data/$L/eval_mfcc exp/$L/tri3/decode_eval_${lm_suffix}
                    grep WER exp/$L/tri3/decode_eval_${lm_suffix}/wer_* | ./utils/best_wer.sh 
                ) &
            done
        fi
    done
    wait;
fi

