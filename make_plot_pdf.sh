#!/bin/bash

FIGURE_DIR=$1
TEXBASE=$(basename ${FIGURE_DIR})
TEXFILE="${TEXBASE}.tex"

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

OUTPUT_DIR=$(dirname ${FIGURE_DIR})
pdflatex -output-directory ${OUTPUT_DIR} ${TEXFILE} > /dev/null
rm ${OUTPUT_DIR}/${TEXBASE}.aux
rm ${OUTPUT_DIR}/${TEXBASE}.log
