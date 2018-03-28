#!/bin/bash

# Copyright 2016 Pegah Ghahremani
#           2017 Andrea Carmantini (Adapted to GlobalPhone)

# This script can be used for training multilingual setup using different
# languages (specifically babel languages) with no shared phones.
# It will generates separate egs directory for each dataset and combine them
# during training.
# In the new multilingual training setup, mini-batches of data corresponding to
# different languages are randomly combined to generate egs.*.scp files
# using steps/nnet3/multilingual/combine_egs.sh and generated egs.*.scp files used
# for multilingual training.
#
# For all languages, we share all except last hidden layer and there is separate final
# layer per language.
# The bottleneck layer can be added to the network structure using --bnf-dim option
#
# The script requires baseline PLP features and alignment (e.g. tri5_ali) for all languages.
# and it will generate 40dim MFCC + pitch features for all languages.
#
# The global iVector extractor is trained using all languages by specifying
# --use-global-ivector-extractor and the iVectors are extracted for all languages.
#
# local.conf should exist (check README.txt), which contains configs for
# multilingual training such as lang_list as array of space-separated languages used
# for multilingual training.
#

echo "$0 $@"  # Print the command line for logging
. ./cmd.sh
set -e

remove_egs=false
remove_ivec=false
use_gpu=true
srand=0
stage=0
train_stage=-10
speed_perturb=false
use_ivector=true
megs_dir=
alidir=sgmm2_4a_ali
suffix=
feat_suffix=_mfcc_hires      # The feature suffix describing features used in
                        # multilingual training
                        # _mfcc_hires -> 40dim MFCC

# language list used for multilingual training
# e.g lang_list=(FR GE)
lang_list=(FR PO GE TH PL KO CZ BG RU VN) # or: RU CZ VN PL KO TH BG PO GE FR
decode_lang_list=("${lang_list[@]}")
lang_list_str=$(echo ${lang_list[@]} | tr ' ' '-')
lang2weight="1.0,1.0"

# language list used for ivector extractor training
# e.g lang_list=(FR GE)
ivec_lang_list=(FR PO GE TH PL KO CZ BG RU VN)
ivec_lang_list_str=$(echo ${ivec_lang_list[@]} | tr ' ' '-')
ivector_extractor=x

bnf_lang_list="CH CR HA SP SW TU"

ivector_suffix=  # if ivector_suffix = _gb, the iVector extracted using global iVector extractor
                   # trained on pooled data from all languages.
                   # Otherwise, it uses iVector extracted using local iVector extractor.
bnf_dim=39           # If non-empty, the bottleneck layer with this dimension is added at two layers before softmax.
dim=625
dir=exp/nnet3/multi/$lang_list_str

num_langs=${#lang_list[@]}
num_ivec_langs=${#ivec_lang_list[@]}

. ./path.sh
. ./utils/parse_options.sh

if $use_gpu && ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

# Check for required files.
for lang_index in `seq 0 $[$num_langs-1]`; do
  for f in data/${lang_list[$lang_index]}/train$feat_suffix/{feats.scp,text} exp/${lang_list[$lang_index]}/$alidir/ali.1.gz exp/${lang_list[$lang_index]}/$alidir/tree; do
    [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
  done
done
# for lang_index in `seq 0 $[$num_ivec_langs-1]`; do
#   for f in data/${ivec_lang_list[$lang_index]}/train$feat_suffix/{feats.scp,text} exp/${ivec_lang_list[$lang_index]}/$alidir/ali.1.gz exp/${ivec_lang_list[$lang_index]}/$alidir/tree; do
#     [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
#   done
# done

if [ "$speed_perturb" == "true" ]; then
  suffix=${suffix}_sp
fi

ivec_feat_suffix=${feat_suffix}
dir=${dir}${suffix}

# Train ivector extractor.
if $use_ivector; then
  ivector_suffix=""
  global_extractor=exp/multi_ivec/${num_ivec_langs}-lang
  ivector_extractor=$global_extractor/extractor
  multi_data_dir_for_ivec=data/multi_ivec/${num_ivec_langs}-lang/train${suffix}${ivec_feat_suffix}
  ivector_suffix=_gb

  if $remove_ivec; then
      echo "Removing existing ivector extractor."
      rm -rd $global_extractor
      rm -rd $multi_data_dir_for_ivec
  fi
  mkdir -p $global_extractor
  mkdir -p $multi_data_dir_for_ivec

  if [ $stage -le 4 ]; then
    $use_gpu && echo "$0: Use CPU before stage 11+" && exit 1;
    echo "$0: combine training data using all langs for training global i-vector extractor."
    if [ ! -f $multi_data_dir_for_ivec/.done ]; then
        echo ---------------------------------------------------------------------
        echo "Pooling training data in $multi_data_dir_for_ivec on" `date`
        echo ---------------------------------------------------------------------
        mkdir -p $multi_data_dir_for_ivec
        combine_lang_list=""
        for lang_index in `seq 0 $[$num_ivec_langs-1]`;do
            combine_lang_list="$combine_lang_list data/${ivec_lang_list[$lang_index]}/train${suffix}${ivec_feat_suffix}"
        done
        utils/combine_data.sh $multi_data_dir_for_ivec $combine_lang_list
        utils/validate_data_dir.sh --no-feats $multi_data_dir_for_ivec
        touch $multi_data_dir_for_ivec/.done
    else
        echo "Not pooling, pooled data already exists in $multi_data_dir_for_ivec."
    fi
    if [ ! -f $ivector_extractor/.done ]; then
        if [ -z $lda_mllt_lang ]; then lda_mllt_lang=${ivec_lang_list[0]}; fi # always true
        echo "$0: Generate global i-vector extractor on pooled data from all "
        echo "languages in $multi_data_dir_for_ivec, using an LDA+MLLT transform trained "
        echo "on ${lda_mllt_lang}."
        local/nnet3/run_shared_ivector_extractor.sh  \
            --suffix "$suffix" --feat-suffix "$ivec_feat_suffix" \
            --stage $stage $lda_mllt_lang \
            $multi_data_dir_for_ivec $global_extractor || exit 1;
        echo ${ivec_lang_list[@]} > $ivector_extractor/ivec_lang_list
        touch $ivector_extractor/.done
    else
        echo "Not training, global i-vector extractor already trained in $global_extractor/extractor"
    fi
    echo "$0: Extracts ivector for all languages using $global_extractor/extractor."
    for lang_index in `seq 0 $[$num_langs-1]`; do
        local/nnet3/extract_ivector_lang.sh --stage $stage \
                                            --train-set train${suffix}${ivec_feat_suffix} \
                                            --ivector-suffix "$ivector_suffix" \
                                            ${lang_list[$lang_index]} \
                                            $ivector_extractor || exit;
    done
  fi
fi

for lang_index in `seq 0 $[$num_langs-1]`; do
  multi_data_dirs[$lang_index]=data/${lang_list[$lang_index]}/train${suffix}${feat_suffix}
  multi_egs_dirs[$lang_index]=exp/${lang_list[$lang_index]}/nnet3/egs
  multi_ali_dirs[$lang_index]=exp/${lang_list[$lang_index]}/${alidir}${suffix}
  multi_ivector_dirs[$lang_index]=exp/${lang_list[$lang_index]}/nnet3${nnet3_affix}/ivectors_train${suffix}${ivec_feat_suffix}${ivector_suffix}
done

if $use_ivector; then
  ivector_dim=$(feat-to-dim scp:${multi_ivector_dirs[0]}/ivector_online.scp -) || exit 1;
else
  echo "$0: Not using iVectors in multilingual training."
  ivector_dim=0
fi
feat_dim=`feat-to-dim scp:${multi_data_dirs[0]}/feats.scp -`
set +x

# Create multilingual neural net config.
if [ $stage -le 9 ]; then
  $use_gpu && echo "$0: Use CPU before stage 11+" && exit 1;
  echo "$0: creating multilingual neural net configs using the xconfig parser";
  if [ -z $bnf_dim ]; then
    bnf_dim=$dim
  fi
  mkdir -p $dir/configs
  ivector_node_xconfig=""
  ivector_to_append=""
  if $use_ivector; then
    ivector_node_xconfig="input dim=$ivector_dim name=ivector"
    ivector_to_append=", ReplaceIndex(ivector, t, 0)"
  fi
  cat <<EOF > $dir/configs/network.xconfig
  $ivector_node_xconfig
  input dim=$feat_dim name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  # the first splicing is moved before the lda layer, so no splicing here
  
  relu-batchnorm-layer name=tdnn1 input=Append(input@-1,input,input@1$ivector_to_append) dim=$dim
  relu-batchnorm-layer name=tdnn2 input=Append(-1,0,1) dim=$dim
  relu-batchnorm-layer name=tdnn3 input=Append(-1,0,1) dim=$dim 
  relu-batchnorm-layer name=tdnn4 input=Append(-3,0,3) dim=$dim
  relu-batchnorm-layer name=tdnn5 input=Append(-3,0,3) dim=$dim
  relu-batchnorm-layer name=tdnn6 input=Append(-6,-3,0) dim=$dim
  relu-batchnorm-layer name=tdnn_bn dim=$bnf_dim
  # adding the layers for diffrent language's output
EOF

  # added separate output layer and softmax for all languages.
  echo $num_langs
  for lang_index in `seq 0 $[$num_langs-1]`;do
    num_targets=`tree-info ${multi_ali_dirs[$lang_index]}/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1;

    echo " relu-batchnorm-layer name=prefinal-affine-lang-${lang_index} input=tdnn_bn dim=$dim"
    echo " output-layer name=output-${lang_index} dim=$num_targets max-change=1.5"
  done >> $dir/configs/network.xconfig

  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig \
    --config-dir $dir/configs/ \
    --nnet-edits="rename-node old-name=output-0 new-name=output"

  cat <<EOF >> $dir/configs/vars
add_lda=false
include_log_softmax=false
EOF

  # removing the extra output node "output-tmp" added for back-compatiblity with
  # xconfig to config conversion.
  nnet3-copy --edits="remove-output-nodes name=output-tmp" $dir/configs/ref.raw $dir/configs/ref.raw || exit 1;
fi

# Prepare egs for each language.
if [ $stage -le 9 ]; then
  $use_gpu && echo "$0: Use CPU before stage 11+" && exit 1;
  echo "$0: Generates separate egs dir per language for multilingual training."
  . $dir/configs/vars || exit 1;
  ivec="${multi_ivector_dirs[@]}"
  if $use_ivector; then
    ivector_opts=(--online-multi-ivector-dirs "$ivec")
  fi
  local/nnet3/prepare_multilingual_egs.sh --cmd "$decode_cmd" \
    "${ivector_opts[@]}" \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --left-context $model_left_context --right-context $model_right_context \
    $num_langs ${multi_data_dirs[@]} ${multi_ali_dirs[@]} ${multi_egs_dirs[@]} || exit 1;
fi

# Combine egs for all languages.
if [ -z $megs_dir ];then
  megs_dir=$dir/egs
fi
if [ $stage -le 10 ] && [ ! -z $megs_dir ]; then
  $use_gpu && echo "$0: Use CPU before stage 11+" && exit 1;
  [ -d $megs_dir ] && rm -rd $megs_dir
  echo "$0: Generate multilingual egs dir using "
  echo "separate egs dirs for multilingual training."
  common_egs_dir="${multi_egs_dirs[@]} $megs_dir"
  steps/nnet3/multilingual/combine_egs.sh \
      --cmd "$decode_cmd" \
      --samples-per-iter 400000 \
      $num_langs ${common_egs_dir[@]} || exit 1;
fi

# Train multilingual DNN.
if [ $stage -le 13 ]; then
    ! $use_gpu && echo "$0: All good. Now use GPU for stage 11-13." && exit 0;
fi

if $use_gpu && [ $stage -le 11 ]; then
  common_ivec_dir=
  if $use_ivector; then
      # Just to get i-vector dim and ID information.
      common_ivec_dir=${multi_ivector_dirs[0]}
  fi
  steps/nnet3/train_raw_dnn.py --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --trainer.num-epochs 2 \
    --trainer.optimization.num-jobs-initial=2 \
    --trainer.optimization.num-jobs-final=2 \
    --trainer.optimization.initial-effective-lrate=0.001 \
    --trainer.optimization.final-effective-lrate=0.0001 \
    --trainer.optimization.minibatch-size=256,128 \
    --trainer.samples-per-iter=400000 \
    --trainer.max-param-change=2.0 \
    --trainer.srand=$srand \
    --feat-dir ${multi_data_dirs[0]} \
    --feat.online-ivector-dir "$common_ivec_dir" \
    --egs.dir $megs_dir \
    --use-dense-targets false \
    --targets-scp ${multi_ali_dirs[0]} \
    --cleanup.remove-egs $remove_egs \
    --cleanup.preserve-model-interval 50 \
    --use-gpu true \
    --dir=$dir  || exit 1;
fi

# Get final language-specific models (by adjusting priors).
if $use_gpu && [ $stage -le 12 ]; then
  for lang_index in `seq 0 $[$num_langs-1]`;do
    lang_dir=$dir/${lang_list[$lang_index]}
    mkdir -p  $lang_dir
    echo "$0: rename output name for each lang to 'output' and "
    echo "add transition model."
    nnet3-copy --edits="rename-node old-name=output-$lang_index new-name=output" \
      $dir/final.raw - | \
      nnet3-am-init ${multi_ali_dirs[$lang_index]}/final.mdl - \
      $lang_dir/final.mdl || exit 1;
    cp $dir/cmvn_opts $lang_dir/cmvn_opts || exit 1;
    echo "$0: compute average posterior and readjust priors for language ${lang_list[$lang_index]}."
    steps/nnet3/adjust_priors.sh --cmd "$decode_cmd" \
      --use-gpu true \
      --iter final --use-raw-nnet false --use-gpu true \
      $lang_dir ${multi_egs_dirs[$lang_index]} || exit 1;
  done
fi

# Extract BNFs.
if $use_gpu && [ $stage -le 13 ]; then
  echo "Extracting BNFs for languages: $bnf_lang_list"
  for lang in $bnf_lang_list; do
    dump_bnf_dir=bnf/$lang
    [ -d $dump_bnf_dir ] && rm -rd $dump_bnf_dir
    mkdir -p $dump_bnf_dir

    for x in eval; do
        datadir=data/$lang/${x}${suffix}${feat_suffix}
        data_bnf_dir=data/$lang/${x}${suffix}_bnf

        ivector_dir=exp/$lang/nnet3${nnet3_affix}/ivectors_${x}${ivec_feat_suffix}${ivector_suffix}
        if $use_ivector; then
            steps/online/nnet2/extract_ivectors_online.sh \
                --cmd "$train_cmd" --nj 5 \
                ${datadir} $ivector_extractor $ivector_dir || exit 1;
            ivector_opts="--ivector-dir $ivector_dir"
        fi

        steps/nnet3/make_bottleneck_features.sh \
            --use-gpu true --nj 5 --cmd "$train_cmd" $ivector_opts \
            tdnn_bn.batchnorm $datadir $data_bnf_dir \
            $dir exp/nnet3/multi/make_train_bnf $dump_bnf_dir || exit 1;
        touch $data_bnf_dir/.done
    done
  done
fi

# Decoding different languages.
if [ $stage -le 14 ]; then
  $use_gpu && echo "$0: All good. Now use CPU for stage 14." && exit 0;
  num_decode_lang=${#decode_lang_list[@]}
  for lang_index in `seq 0 $[$num_decode_lang-1]`; do
    for decode_set in dev; do
      (
        if [ ! -f $dir/${decode_lang_list[$lang_index]}/decode_${decode_set}/.done ]; then
            echo "Decoding lang ${decode_lang_list[$lang_index]} using multilingual hybrid model $dir"
            local/nnet3/run_decode_lang.sh --use-ivector $use_ivector --iter final_adj \
                                           --dir ${decode_set} \
                                           ${decode_lang_list[$lang_index]} $dir \
                                           $ivector_extractor || exit 1;
            touch $dir/${decode_lang_list[$lang_index]}/decode_${decode_set}/.done
            grep WER $dir/${decode_lang_list[$lang_index]}/decode_${decode_set}/wer_* | ./utils/best_wer.sh
        else
            echo "Already decoded, delete $dir/${decode_lang_list[$lang_index]}/decode_${decode_set}/.done to decode"
        fi
      ) &
    done
  done
  wait;
fi
