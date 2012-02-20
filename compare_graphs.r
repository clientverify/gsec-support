#!/usr/bin/Rscript

args=paste(commandArgs(), " ")

colnames = c(
"STATS","round","activestates","erases","prunes",
"time","time_user","prune_time","mergetime",
"searchertime","solvertime","forktime", "roundinsts",
"totalstates", "mem"
)

plotnames = c(
"time","solvertime", "roundinsts","totalstates", "mem"
)
plotwidth=11
plotheight=7

root_dir="/home/rac/research/gsec/results"
data_dir="data"
output_dir="plots"
output_filetype="png"

data_subdirs = c('editcost','vanilla')

min_size=.Machine$integer.max
data = NULL

for (i in seq(length(data_subdirs))) {
  fullpath = paste(root_dir, data_dir, data_subdirs[i], sep="/")
  for (file in list.files(path=fullpath)) {
    tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=colnames), silent=TRUE)
    if (class(tmp_data) != "try-error") {
      len = length(tmp_data[,1]) # length of rows, not cols
      min_size = min(min_size, len)
      tmp_data$name=rep(file, len)
      tmp_data$mode=rep(data_subdirs[i], len)
      data = rbind(data, tmp_data)
    }
  }
}

library(ggplot2)

for (p in plotnames) {
  x_axis = "round"
  ggplot(data, aes_string(x=x_axis, y=p)) + geom_line(aes(colour=factor(mode))) + facet_grid(. ~ name)
  name = paste(paste("stat",p,sep="-"), "geom-line", sep="_")
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(root_dir, output_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

for (p in plotnames) {
  x_axis = "round"
  ggplot(data, aes_string(x=x_axis, y=p)) + geom_point(aes(colour=factor(mode))) + scale_y_log10() + facet_grid(. ~ name)
  name = paste(paste("stat",p,sep="-"), "geom-point", "yscale-log10", sep="_")
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(root_dir, output_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

for (p in plotnames) {
  ggplot(subset(data, round < min_size), aes_string(x="mode", y=p)) + stat_summary(fun.y="sum", geom="bar")
  name = paste(paste("stat",p,sep="-"), "func-sum", "geom-bar", sep="_")
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(root_dir, output_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
