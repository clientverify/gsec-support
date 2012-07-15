#!/usr/bin/Rscript

args=commandArgs(trailingOnly=TRUE)

library(ggplot2)
library(reshape)

# cbgColourPalette <- scale_colour_manual(values=c("#999999", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"))
cbgColourPalette <- scale_colour_manual(values=c("#0072B2", "#56B4E9", "#E69F00", "#009E73", "#F0E442", "#999999", "#D55E00", "#CC79A7"))

old_colnames = c(
"STATS","round","activestates","erases","prunes",
"time","timeuser","prunetime","mergetime",
"searchertime","solvertime","forktime", "roundinsts",
"totalstates", "mem"
)

oldoldcolnames = c(
"STATS","Round","ActiveStates",
"Time","TimeUser","PruneTime","MergeTime",
"SearcherTime","RebuildTime", "InstructionsExecuted",
"CurrentStates", "CummulativeStates", "AllocatedMemoryAtEndOfRound",
"ExecutionTreeTime", "ExecutionTreeExtendTime", 
"EditDistanceComputeTime", "EditDistanceBuildTime", "EditDistanceTreeSize",
"EditDistanceFinalK", "EditDistanceMinScore","StageCount","SelfPathEditDistance"
)
colnames = c(
  "STATS","Round","ActiveStates","MergedStates","PrunedConstraints",
  "Time","TimeUser","PruneTime","MergeTime",
  "SearcherTime","SolverTime", "ForkTime", "RebuildTime", "InstructionsExecuted",
  "CurrentStates", "CummulativeStates", "AllocatedMemoryAtEndOfRound",
  "ExecutionTreeTime", "ExecutionTreeExtendTime", 
  "EditDistanceComputeTime", "EditDistanceBuildTime", "EditDistanceTreeSize",
  "EditDistanceFinalK", "EditDistanceMinScore","StageCount","SelfPathEditDistance"
  )
oldcolnames = c(
  "STATS","Round","ActiveStates",
  "Time","TimeUser","PruneTime","MergeTime",
  "SearcherTime","RebuildTime", "InstructionsExecuted",
  "CurrentStates", "CummulativeStates", "AllocatedMemoryAtEndOfRound",
  "ExecutionTreeTime", "ExecutionTreeExtendTime", 
  "EditDistanceComputeTime", "EditDistanceBuildTime", "EditDistanceTreeSize",
  "EditDistanceFinalK", "EditDistanceMinScore","StageCount"
  )
# colnames = c(
# "STATS","Round","ActiveStates",
# "Time","TimeUser","PruneTime","MergeTime",
# "SearcherTime","RebuildTime", "InstructionsExecuted",
# "CurrentStates", "CummulativeStates", "AllocatedMemoryAtEndOfRound"
# )

#plotnames = c(
#"Time","InstructionsExecuted","CummulativeStates", "EditDistanceTreeSize", "EditDistanceMinScore", "StageCount", "EditDistanceFinalK", "AllocatedMemoryAtEndOfRound", "ExecutionTreeTime"
#)

plotnames = c(
  "Time","InstructionsExecuted", "EditDistanceTreeSize", "EditDistanceMinScore", "StageCount", "EditDistanceFinalK", "AllocatedMemoryAtEndOfRound", "ExecutionTreeTime"
  )

plotwidth=9
default_plotheight=6

root_dir="/home/rac/research/test.gsec/results/xpilot-ng-x11"
#root_dir="/home/rac/research/test.gsec/results/tetrinet-klee"

if (length(args) > 0) {
  root_dir = args[1]
}

data_dir="data"
output_dir="plots"
output_filetype="png"

#create output dirs
save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
#data_save_dir = paste(save_dir,"data_used",sep="/")
dir.create(save_dir, recursive=TRUE)
#dir.create(data_save_dir, recursive=TRUE)

min_size=.Machine$integer.max
data = NULL

previous_count = 1

for (data_subdir in dir(paste(root_dir,data_dir,sep="/"), full.names=FALSE, recursive=FALSE)) {
  data_path = paste(root_dir, data_dir, data_subdir, sep="/")
  data_ids = NULL
  for (id in dir(data_path, full.names=FALSE, recursive=FALSE)) {
    data_ids = c(data_ids, id)
  }
  
  data_ids = sort(data_ids, decreasing=TRUE)

  for (i in seq(min(length(data_ids), previous_count))) {
    fullpath = paste(data_path, data_ids[i], sep="/")
    file_count = 0
    for (file in list.files(path=fullpath)) {
      tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=colnames), silent=TRUE)
#       if (class(tmp_data) == "try-error") {
#         tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=oldcolnames), silent=TRUE)
#         len = length(tmp_data[,1])
#         tmp_data$SelfPathEditDistance = rep(0,len)
#       }
      if (class(tmp_data) != "try-error") {
        file_count = file_count+1
        ## copy the data file
        #file.copy(paste(fullpath,file,sep="/"),paste(data_save_dir,file,sep="/"),overwrite=TRUE)
        len = length(tmp_data[,1]) # length of rows, not cols
        min_size = min(min_size, len)
        cat(data_subdir,'\t',i,'\t',len,'\n')
        tmp_data$name=rep(paste("LOG", sprintf("%02d",file_count)), len)
        #tmp_data$name=rep(substr(file,1, 10), len)
        #tmp_data$mode=rep(data_subdir, len)
        #tmp_data$version=rep(data_id[i], len)
        tmp_data$mode=rep(paste(data_subdir,i,sep=","), len)
#         if (data_subdir == "naive") {
#           tmp_data$Round = tmp_data$Round + 1
#         }
        
        #tmp_data = subset(tmp_data, Round < (len - 2))
        data = rbind(data, tmp_data)
      } else {
        cat("Error: ", data_subdir,'\t',i,'\n')
      }
    }
  }
}

# Compute the time not spent in ExecutionTree
data$ExecTime = data$Time - data$ExecutionTreeTime

###temp
#data = subset(data, name != "LOG 01" & name != "LOG 05")
#data = subset(data, name != "LOG 06")
#data = subset(data, mode != "nc-ed-row,1" & mode != "self-edit-dist-row,1")
#data = subset(data, name == "LOG 06" | name == "LOG 05")

#min_size = min_size - 10
start_round = -1

min_size = max(data$Round)
#min_size = min_size - 5
legend_rows = ceiling(length(unique(factor(data$mode)))/3)

cat("start round: ",start_round,", min_size: ",min_size,"\n")


plotheight = length(unique(data$name))
for (y_axis in plotnames) {
 x_axis = "Round"
 cat("plotting: ",x_axis," vs ",y_axis,"\n")
 name = paste("plot","line",paste(x_axis,"vs",y_axis,sep=""),sep="_")
 title = paste(x_axis,"vs",y_axis, sep=" ")
 p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=x_axis, y=y_axis))
 
 p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5)
 #p = p + scale_fill_hue("Algorithm")
 p = p + facet_grid(name ~ .)
 p = p + theme_bw()
 #p = p + cbgColourPalette
 p = p + opts(title=title,legend.position="bottom")
 p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
 p;  
 filename = paste(name, output_filetype, sep=".")
 ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
 
# plotheight = length(unique(data$name))
# for (y_axis in plotnames) {
#  x_axis = "Round"
#  cat("plotting (log scale): ",x_axis," vs ",y_axis,"\n")
#  name = paste("plot","line","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
#  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
#  p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=x_axis, y=y_axis))
#  p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
#  p = p + scale_y_log10() 
#  p = p + theme_bw() 
#  #p = p + cbgColourPalette
#  p = p + facet_grid(name ~ .) 
#  p = p + opts(title=title,legend.position="bottom")
#  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
#  p;
#  filename = paste(name, output_filetype, sep=".")
#  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
# }

plotheight = default_plotheight
for (y_axis in plotnames) {
  name =  paste("plot","bar",y_axis,sep="_")
  cat("plotting (summary): ",x_axis," vs ",y_axis,"\n")
  title = paste("Summary of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray") 
  p = p + theme_bw() 
  #p = p + cbgColourPalette
  p = p + opts(title=title, axis.title.x=theme_blank(), axis.text.x=theme_text(angle=-90))
  #p = p + opts(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

plotheight = default_plotheight*2
for (y_axis in plotnames) {
  name =  paste("plot","mean_bar",y_axis,sep="_")
  cat("plotting (mean of): ",x_axis," vs ",y_axis,"\n")
  title = paste("Mean of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray") 
  p = p + theme_bw()
  #p = p + facet_grid(name ~ .)
  #p = p + cbgColourPalette
  p = p + opts(title=title, axis.title.x=theme_blank(), axis.text.x=theme_text(angle=-90))
  #p = p + opts(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}