#!/usr/bin/Rscript

args=paste(commandArgs(), " ")

# cbgColourPalette <- scale_colour_manual(values=c("#999999", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"))
cbgColourPalette <- scale_colour_manual(values=c("#0072B2", "#56B4E9", "#E69F00", "#009E73", "#F0E442", "#999999", "#D55E00", "#CC79A7"))

colnames = c(
"STATS","round","activestates","erases","prunes",
"time","timeuser","prunetime","mergetime",
"searchertime","solvertime","forktime", "roundinsts",
"totalstates", "mem"
)

plotnames = c(
"time","solvertime", "roundinsts", "mem"
)
plotwidth=9
plotheight=6

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
      tmp_data$name=rep(substr(file,6, 7), len)
      tmp_data$mode=rep(data_subdirs[i], len)
      data = rbind(data, tmp_data)
    }
  }
}

min_size = min_size - 1

library(ggplot2)

for (pname in plotnames) {
  x_axis = "round"
  name = paste(paste("stat",pname,sep="-"), "geom-line", sep="_")
  p = ggplot(subset(data, round < min_size), aes_string(x=x_axis, y=pname))
  p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=1)
  p = p + scale_fill_hue("Algorithm")
  p = p + facet_grid(name ~ .)
  p = p + theme_bw()
  p = p + cbgColourPalette
  p = p + opts(title=name)
  p;  
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(root_dir, output_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

for (p in plotnames) {
  x_axis = "round"
  name = paste(paste("stat",p,sep="-"), "geom-line", "yscale-log2", sep="_")
  theplot <- ggplot(subset(data, round < min_size), aes_string(x=x_axis, y=p)) 
  theplot + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=1) + scale_y_log2() + theme_bw() + facet_grid(name ~ .) + opts(title=name)
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(root_dir, output_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

for (p in plotnames) {
  name = paste(paste("stat",p,sep="-"),paste("round","lt",min_size,sep="-"),"func-sum","geom-bar",sep="_")
  theplot <- ggplot(subset(data, round < min_size), aes_string(x="mode", y=p)) 
  theplot + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray") + theme_bw() + opts(title=name)
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(root_dir, output_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
