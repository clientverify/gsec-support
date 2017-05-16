#!/bin/bash

###############################################################################
### Use Latex to generate a PDF from a directory of figures images
###############################################################################

set -u # Exit if uninitialized value is used
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ERROR_EXIT=1
PROG=$(basename $0)

# gsec_common required variables
ROOT_DIR="`pwd`"
VERBOSE_OUTPUT=0

# Include gsec_common
. $HERE/build_configs/gsec_common

FIGURE_DIR=$1
if [ "$#" -ne 1 ]
then
  echo -e "Usage:\nGenerate PDF with Latex from directory of figures.\n\t$0: [directory of figures]"
  exit 1
fi

FIGURE_TYPE="png"
OUTPUT_DIR=$(dirname ${FIGURE_DIR})
TEXBASE=$(basename ${FIGURE_DIR})
TEXFILE="${OUTPUT_DIR}/${TEXBASE}.tex"
PDFFILE="${OUTPUT_DIR}/${TEXBASE}.pdf"

FIGURE_COUNT=$(find ${FIGURE_DIR} -follow -maxdepth 1 -iname "*.${FIGURE_TYPE}" | wc -l)
lecho "Generating $(basename ${PDFFILE}) from ${FIGURE_COUNT} figures"

TEXHEADER="\documentclass[letterpaper,twocolumn,10pt]{article} \usepackage{graphicx} \usepackage{url} \renewcommand{\figurename}{} \begin{document}"
FIGURE_TEMPLATE="
\\\\begin{figure}[t]
\\\\centering
\\\\includegraphics[width=\\\\columnwidth]{%s}\\\\\\\\
\\\\caption{\\\\protect\\\\url{%s}}
\\\\end{figure}"

TEXFOOTER="\end{document}"

echo ${TEXHEADER} > ${TEXFILE}

plot_count=0
for fullPathPlot in ${FIGURE_DIR}/*
do
  plot=$(basename $fullPathPlot)
  #echo "Adding ${FIGURE_DIR}/${plot} from ${fullPathPlot}"
  printf "${FIGURE_TEMPLATE}\n" "${FIGURE_DIR}/${plot}" "${plot}" >> ${TEXFILE}
  plot_count=$((plot_count + 1))
  if ! ((plot_count % 8)); then
    echo "\clearpage" >> ${TEXFILE}
  fi
done
echo ${TEXFOOTER} >> ${TEXFILE}

# Generate PDF from latex
pdflatex -output-directory ${OUTPUT_DIR} ${TEXFILE} > /dev/null

# Delete intermediate files
rm ${TEXFILE}
rm ${OUTPUT_DIR}/${TEXBASE}.aux
rm ${OUTPUT_DIR}/${TEXBASE}.log
