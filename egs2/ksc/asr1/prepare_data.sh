#!/usr/bin/env bash
#
# Copyright  2014  Nickolay V. Shmyrev
#            2014  Brno University of Technology (Author: Karel Vesely)
#            2016  Johns Hopkins University (Author: Daniel Povey)
#            2021  UCAS (author: Keqi Deng)
#            2023  (author: Dongwei Jiang)
# Apache 2.0

# To be run from one directory above this script.

. ./path.sh

KSC=$1

export LC_ALL=C

sph2pipe=sph2pipe

# Prepare: test, train, dev
for set in dev test train; do
  dir=data/$set.orig
  mkdir -p $dir

  # Prepare 'text' file
  # - {NOISE} -> [NOISE] : map the tags to match symbols in dictionary
  cat $dir/stm | grep -v -e 'ignore_time_segment_in_scoring' -e ';;' | \
    awk '{ printf ("%s-%07d-%07d", $1, $4*100, $5*100);
           for (i=7;i<=NF;i++) { printf(" %s", $i); }
           printf("\n");
         }' | tr '{}' '[]' | tr '<' '[' | tr '>' ']' | sort -k1,1 > $dir/text || exit 1

  # Prepare 'segments', 'utt2spk', 'spk2utt'
  cat $dir/text | cut -d" " -f 1 | awk -F"-" '{printf("%s %s %07.2f %07.2f\n", $0, $1, $2/100.0, $3/100.0)}' > $dir/segments
  cat $dir/segments | awk '{print $1, $2}' > $dir/utt2spk
  cat $dir/utt2spk | utils/utt2spk_to_spk2utt.pl > $dir/spk2utt

  # Prepare 'wav.scp', 'reco2file_and_channel'
  cat $dir/spk2utt | awk -v data_type=$data_type -v set=$set -v pwd=$PWD '{ printf("%s '$sph2pipe' -f wav -p '$TEDLIUM3'/TEDLIUM_release-3/%s/%s/sph/%s.sph |\n", $1, data_type, set, $1); }' > $dir/wav.scp
  cat $dir/wav.scp | awk '{ print $1, $1, "A"; }' > $dir/reco2file_and_channel

  # Create empty 'glm' file
  echo ';; empty.glm
  [FAKE]     =>  %HESITATION     / [ ] __ [ ] ;; hesitation token
  ' > data/$set.orig/glm

  # The training set seems to not have enough silence padding in the segmentations,
  # especially at the beginning of segments.  Extend the times.
  if [ $set == "train" ]; then
    mv data/$set.orig/segments data/$set.orig/segments.temp
    utils/data/extend_segment_times.py --start-padding=0.15 \
      --end-padding=0.1 <data/$set.orig/segments.temp >data/$set.orig/segments || exit 1
    rm data/$set.orig/segments.temp
  fi

  # Check that data dirs are okay!
  utils/validate_data_dir.sh --no-feats $dir || exit 1
done


# create extra LM training data from external Tedlium3
mkdir -p data/local


# remove non-english characters and text that are too long
gunzip -c $TEDLIUM3/TEDLIUM_release-3/LM/*.en.gz | sed 's/ <\/s>//g' | local/join_suffix.py | awk '{printf "%d %s\n", NR, $0}' | egrep -v '[^a-zA-Z0-9[:space:][:punct:]]' | awk '{print NF, $0}' | sort -n | awk -v max_wc="100" '$1 <= max_wc {print $0}' | cut -f2- -d' ' > data/local/text
