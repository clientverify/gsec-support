#!/usr/bin/Rscript

args=commandArgs(trailingOnly=TRUE)

library(ggplot2)

# cbgColourPalette <- scale_colour_manual(values=c("#999999", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"))
cbgColourPalette <- scale_colour_manual(values=c("#0072B2", "#56B4E9", "#E69F00", "#009E73", "#F0E442", "#999999", "#D55E00", "#CC79A7"))

old_colnames = c(
"STATS","round","activestates","erases","prunes",
"time","timeuser","prunetime","mergetime",
"searchertime","solvertime","forktime", "roundinsts",
"totalstates", "mem"
)

colnames = c(
"STATS","Round","ActiveStates",
"Time","TimeUser","PruneTime","MergeTime",
"SearcherTime","RebuildTime", "InstructionsExecuted",
"CurrentStates", "CummulativeStates", "AllocatedMemoryAtEndOfRound",
"ExecutionTreeTime", "ExecutionTreeExtendTime", 
"EditDistanceComputeTime", "EditDistanceBuildTime", "EditDistanceTrainingTreeSize"
)

# colnames = c(
# "STATS","Round","ActiveStates",
# "Time","TimeUser","PruneTime","MergeTime",
# "SearcherTime","RebuildTime", "InstructionsExecuted",
# "CurrentStates", "CummulativeStates", "AllocatedMemoryAtEndOfRound"
# )

plotnames = c(
"Time","InstructionsExecuted","CummulativeStates", "AllocatedMemoryAtEndOfRound"
)

plotwidth=9
plotheight=6

root_dir="/home/rac/research/test.gsec/results/xpilot-ng-x11"

if (length(args) > 0) {
  root_dir = args[1]
}

data_dir="data"
output_dir="plots"
output_filetype="png"

#create output dirs
save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
data_save_dir = paste(save_dir,"data_used",sep="/")
dir.create(save_dir, recursive=TRUE)
dir.create(data_save_dir, recursive=TRUE)

min_size=.Machine$integer.max
data = NULL

previous_count = 2

for (data_subdir in dir(paste(root_dir,data_dir,sep="/"), full.names=FALSE, recursive=FALSE)) {
  data_path = paste(root_dir, data_dir, data_subdir, sep="/")
  data_ids = NULL
  for (data_id in dir(data_path, full.names=FALSE, recursive=FALSE)) {
    data_ids = c(data_ids, data_id)
  }
  sort(data_ids, decreasing=TRUE)
  for (i in seq(min(length(data_ids), previous_count))) {
    fullpath = paste(data_path, data_id[i], sep="/")
    for (file in list.files(path=fullpath)) {
      tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=colnames), silent=TRUE)
      if (class(tmp_data) != "try-error") {
        # copy the data file
        file.copy(paste(fullpath,file,sep="/"),paste(data_save_dir,file,sep="/"),overwrite=TRUE)
        len = length(tmp_data[,1]) # length of rows, not cols
        min_size = min(min_size, len)
        tmp_data$name=rep(substr(file,1, 10), len)
        #tmp_data$name=rep(file, len)
        tmp_data$mode=rep(data_subdir, len)
        tmp_data$version=rep(data_id[i], len)
        data = rbind(data, tmp_data)
      }
    }
  }
}

#min_size = 10

for (y_axis in plotnames) {
  x_axis = "Round"
  name = paste("plot","line",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  p = ggplot(subset(data, Round < min_size & Round > 0), aes_string(x=x_axis, y=y_axis))
  p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=1)
  p = p + scale_fill_hue("Algorithm")
  p = p + facet_grid(name ~ .)
  p = p + theme_bw()
  p = p + cbgColourPalette
  p = p + opts(title=title)
  p;  
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

for (y_axis in plotnames) {
  x_axis = "Round"
  name = paste("plot","line","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  p = ggplot(subset(data, Round < min_size & Round > 0), aes_string(x=x_axis, y=y_axis))
  p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=1) 
  p = p + scale_y_log10() 
  p = p + theme_bw() 
  p = p + facet_grid(name ~ .) 
  p = p + opts(title=title)
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

for (y_axis in plotnames) {
  name =  paste("Plot","bar",y_axis,sep="_")
  title = paste("Summary of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > 0), aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray") 
  p = p + theme_bw() 
  p = opts(title=title)
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
