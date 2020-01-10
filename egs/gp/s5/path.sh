# This contains the locations of the tools and data required for running
# the GlobalPhone experiments.

export LC_ALL=C  # For expected sorting and joining behaviour

#KALDI_ROOT=/group/project/cstr2/enno/kaldi
KALDI_ROOT=/fs/clip-software/user-supported/kaldi
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh

[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh

FSTBIN=$KALDI_ROOT/tools/openfst/bin
LMBIN=$KALDI_ROOT/tools/irstlm/bin

#export PATH=$PWD/utils/:$PWD/local/:$FSTBIN:$LMBIN:$PWD:$PATH
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$PWD:$PATH

# If the correct version of shorten and sox are not on the path,
# the following will be set by local/gp_check_tools.sh
SHORTEN_BIN=$PWD/tools/shorten-3.6.1/bin
# e.g. $PWD/tools/shorten-3.6.1/bin
SOX_BIN=$PWD/tools/sox-14.3.2/bin
# e.g. $PWD/tools/sox-14.3.2/bin

export PATH=$PATH:$SHORTEN_BIN
export PATH=$SOX_BIN:$PATH

# Set the locations of the GlobalPhone corpus and language models
export GP_CORPUS=/fs/clip-realspeech/projects/bnfs/gpdata
export GP_LM=/fs/clip-realspeech/projects/bnfs/gplms
export ALIGN_DIR=$PWD/language_models
