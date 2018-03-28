#!/bin/bash

# Copyright 2017 John Morgan
# Apache 2.0.
# from github.com/johnjosephmorgan/gp_korean

# NB: The supplied GlobalPhone LM for Korean uses Hangul, while the corpus
# itself is romanized, hence the need to create our own LM. The corpus is
# syllabified, so this is a syllable 3-gram LM.

. ./cmd.sh
set -e
. ./path.sh

. ./utils/parse_options.sh

if [ ! -d data/KO/local/lm ]; then
    mkdir -p data/KO/local/lm
fi


corpus=data/KO/local/lm/training_text.txt
cut -f 2- -d ' ' data/KO/train/text > $corpus

ngram-count \
    -order 3 \
    -interpolate \
    -unk \
    -map-unk "<unk>" \
    -limit-vocab \
    -text $corpus \
    -lm data/KO/local/lm/3gram.arpa || exit 1;

if [ -e "data/KO/local/lm/3gram.arpa.gz" ]; then
    rm data/KO/local/lm/3gram.arpa.gz
fi

gzip \
    data/KO/local/lm/3gram.arpa

rm $corpus
