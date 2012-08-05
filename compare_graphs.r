#!/usr/bin/Rscript

args=commandArgs(trailingOnly=TRUE)

library(ggplot2)
library(reshape)
library(scales)
library(quantreg)

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
  "EditDistanceFinalK", "EditDistanceMinScore","StageCount","SelfPathEditDistance", "TrainingTime",
  "RecvInstructionsExecuted"
  )

prev2_colnames = c(
  "STATS","Round","ActiveStates","MergedStates","PrunedConstraints",
  "Time","TimeUser","PruneTime","MergeTime",
  "SearcherTime","SolverTime", "ForkTime", "RebuildTime", "InstructionsExecuted",
  "CurrentStates", "CummulativeStates", "AllocatedMemoryAtEndOfRound",
  "ExecutionTreeTime", "ExecutionTreeExtendTime", 
  "EditDistanceComputeTime", "EditDistanceBuildTime", "EditDistanceTreeSize",
  "EditDistanceFinalK", "EditDistanceMinScore","StageCount","SelfPathEditDistance", "TrainingTime"
  )
prev_colnames = c(
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
  "Time",
  "InstructionsExecuted", 
  "SendInstructionsExecuted", 
#  "EditDistanceTreeSize", 
#  "StageCount", 
#  "EditDistanceFinalK", 
#  "AllocatedMemoryAtEndOfRound", 
#  "ExecutionTreeTime", 
#  "TrainingTime", 
#  "ExecTime", 
  "TimeMinus",
  "TimeWOSolver"
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
output_filetype="eps"

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
      if (class(tmp_data) == "try-error") {
        tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=prev_colnames), silent=TRUE)
        if (class(tmp_data) != "try-error") {
          len = length(tmp_data[,1])
          #tmp_data$SelfPathEditDistance = rep(0,len)
          tmp_data$RecvInstructionsExecuted = rep(0,len)
        }
      }
      if (class(tmp_data) == "try-error") {
        tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=prev2_colnames), silent=TRUE)
        len = length(tmp_data[,1])
        #tmp_data$SelfPathEditDistance = rep(0,len)
        tmp_data$TrainingTime = rep(0,len)
        tmp_data$RecvInstructionsExecuted = rep(0,len)
      }

         
      if (class(tmp_data) != "try-error") {
        file_count = file_count+1
        ## copy the data file
        #file.copy(paste(fullpath,file,sep="/"),paste(data_save_dir,file,sep="/"),overwrite=TRUE)
        len = length(tmp_data[,1]) # length of rows, not cols
        min_size = min(min_size, len)
        cat(data_subdir,'\t',i,'\t',len,'\t',data_ids[i],'\t',file,'\n')
        #tmp_data$name=rep(paste("Trace", sprintf("%02d",file_count)), len)
        #tmp_data$name=rep(sprintf("%02d",file_count), len)
        
        tmp_data$name=rep(substr(file,8, 9), len)
        
        #tmp_data$mode=rep(data_subdir, len)
        #tmp_data$version=rep(data_id[i], len)
        if (previous_count > 1) {
          tmp_data$mode=rep(paste(data_subdir,i,sep=","), len)
        } else {
          tmp_data$mode=rep(data_subdir, len)
        }
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
#data$ExecTime = data$Time - data$ExecutionTreeTime

#data$TimeMinus = data$Time - data$TrainingTime - data$ExecutionTreeTime

data$SendInstructionsExecuted = data$InstructionsExecuted - data$RecvInstructionsExecuted

data$TimeMinus = data$Time - (data$EditDistanceComputeTime)*0.25


data$TimeWOSolver = data$Time - data$SolverTime

###temp
#data = subset(data, name != "LOG 07" & name != "LOG 09" & name != "LOG 04")
#data = subset(data, name != "LOG 19" & name != "LOG 18")
#data = subset(data, name != "21")
#data = subset(data, mode != "nc-ed-row,1" & mode != "self-edit-dist-row,1")
#data = subset(data, name == "LOG 04" | name == "LOG 07")

min_size = min_size - 10
start_round = 2

#min_size = max(data$Round)
#min_size = min_size - 5
legend_rows = ceiling(length(unique(factor(data$mode)))/3)

cat("start round: ",start_round,", min_size: ",min_size,"\n")

data = subset(data, (Round < min_size) & (Round > start_round))

plotheight = length(unique(data$name))

if (1) {
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
}
 
if (1) {
plotheight = length(unique(data$name))
for (y_axis in plotnames) {
 x_axis = "Round"
 cat("plotting (log scale): ",x_axis," vs ",y_axis,"\n")
 name = paste("plot","line","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
 title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
 p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=x_axis, y=y_axis))
 p = p + geom_point(aes(colour=factor(mode),linetype=factor(mode)),size=0.5)
 #p = p + stat_quantile(aes(colour=factor(mode),quantiles = 0.95))
 p = p + scale_y_log10() 
 p = p + theme_bw() 
 #p = p + cbgColourPalette
 p = p + facet_grid(name ~ .) 
 p = p + opts(title=title,legend.position="bottom")
 p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
 p;
 filename = paste(name, output_filetype, sep=".")
 ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
}
if (0) {
plotheight = length(unique(data$name))
for (y_axis in plotnames) {
  x_axis = "Round"
  cat("plotting (log scale): ",x_axis," vs ",y_axis,"\n")
  name = paste("plot","histogram","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=y_axis))
  p = p + geom_histogram() 
  p = p + scale_y_log10() 
  p = p + theme_bw() 
  #p = p + cbgColourPalette
  p = p + facet_grid(name ~ .) 
  p = p + opts(title=title,legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
}

if (0) {
plotheight = default_plotheight*2
for (y_axis in plotnames) {
  x_axis = "Round"
  name =  paste("plot","bar",y_axis,sep="_")
  cat("plotting (summary): ",x_axis," vs ",y_axis,"\n")
  title = paste("Summary of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray") 
  p = p + theme_bw() 
  p = p + facet_grid(name ~ .)
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
  x_axis = "Round"
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
}

plotheight = default_plotheight 
for (y_axis in plotnames) {
  x_axis = "Round"
  name =  paste("plot","boxplot_bar",y_axis,sep="_")
  cat("plotting (boxplot of): ",x_axis," vs ",y_axis,"\n")
  title = paste("Boxplot of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x="mode", y=y_axis), aes(ymin = "0%", lower = "25%", middle = "50%", upper = "75%", ymax = "100%")) 
  #p <- ggplot(subset(data, Round < min_size & Round > start_round), aes(x=mode, y=Time, ymin = `0%`, lower = `25%`, middle = `50%`, upper = `75%`, ymax = `100%`)) 
  #p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray")
  #p = p + geom_boxplot(aes(colour=factor(mode),linetype=factor(mode)))
  p = p + geom_boxplot(aes(colour=factor(mode),linetype=factor(mode)),outlier.size=1.0) + scale_fill_brewer(palette="OrRd")
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=2)
  #p = p + scale_y_log10()
  p = p + scale_x_discrete()
  #p = p + scale_y_continuous(trans = log_trans(10))
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)))
  p = p + theme_bw()
  p = p + facet_grid(. ~ name)
  #p = p + opts(legend.background = theme_rect(), legend.justification=c(0,1), legend.position=c(0,1), legend.title=theme_blank(), axis.title.x = theme_blank(), axis.text.x = theme_blank(), axis.ticks.x = theme_blank()) + ylab("Time (s)")
  #p = p + opts(axis.title.x = theme_blank(), axis.text.x = theme_blank(), axis.ticks.x = theme_blank()) + ylab("Time (s)")
  #p = p + opts(ylab("Time (s)")
  p = p + opts(legend.position="none", axis.text.x=theme_text(angle=45))
  #p = p + cbgColourPalette
  #p = p + opts(title=title, axis.title.x=theme_blank(), axis.text.x=theme_text(angle=-90))
  #p = p + opts(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
