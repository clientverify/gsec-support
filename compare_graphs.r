#!/usr/bin/Rscript

args=commandArgs(trailingOnly=TRUE)

library(ggplot2)
library(reshape)
library(scales)
library(quantreg)

# cbgColourPalette <- scale_colour_manual(values=c("#999999", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"))
cbgColourPalette <- scale_colour_manual(values=c("#0072B2", "#56B4E9", "#E69F00", "#009E73", "#F0E442", "#999999", "#D55E00", "#CC79A7"))

colnames = c(
  "STATS","Round","Time","TimeReal","TimeSys",
  "SolverTime","SearcherTime","ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime",
  "Instructions","RecvInstructions",
  "StageCount","MergedStates","StateCount","TotalStates","Memory"
)

plotnames = c(
  "Time",
  "Instructions", 
  "Memory", 
  "Delay"
)

default_plotwidth=5
default_plotheight=5
heightscalefactor = 2.0

root_dir="/home/rac/research/test.gsec/results.test/xpilot-ng-x11"
#root_dir="/home/rac/research/test.gsec/results/tetrinet-klee"

if (length(args) > 0) {
  root_dir = args[1]
}

data_dir="data"
output_dir="plots"
output_filetype="eps"

#create output dirs
save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
dir.create(save_dir, recursive=TRUE)

min_size=.Machine$integer.max
data = NULL

previous_count = 1
binwidth=20

if (1) {
  ts0 = read.table(paste(paste(root_dir,data_dir,sep="/"),"timestamps_0.csv",sep="/"),col.names=c('timestamp'))
  ts1 = read.table(paste(paste(root_dir,data_dir,sep="/"),"timestamps_1.csv",sep="/"),col.names=c('timestamp'))
  ts0$timestamp = ts0$timestamp - rep(ts0$timestamp[1],length(ts0[,1]))
  ts1$timestamp = ts1$timestamp - rep(ts1$timestamp[1],length(ts1[,1]))
  ts_len = min(length(ts0[,1]),length(ts1[,1]))
  cat(ts_len,'\n')
  tsavg = (ts0$timestamp[seq(ts_len)] + ts1$timestamp[seq(ts_len)]) / rep(2,ts_len)
  cat(length(ts0[,1]),'\n')
  ts = ts1
  tsdur = c(0)
  tsdur = append(tsdur,tsavg)
  tsc = tsavg - tsdur[seq(ts_len)]
  d = mean(tsc)
  cat(d,'\n')
  
}

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
      #if (class(tmp_data) == "try-error") {
      #  tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=prev_colnames), silent=TRUE)
      #  if (class(tmp_data) != "try-error") {
      #    len = length(tmp_data[,1])
      #    #tmp_data$SelfPathEditDistance = rep(0,len)
      #    tmp_data$RecvInstructionsExecuted = rep(0,len)
      #  }
      #}
      #if (class(tmp_data) == "try-error") {
      #  tmp_data = try(read.table(paste(fullpath,file,sep="/"), col.names=prev2_colnames), silent=TRUE)
      #  len = length(tmp_data[,1])
      #  #tmp_data$SelfPathEditDistance = rep(0,len)
      #  tmp_data$TrainingTime = rep(0,len)
      #  tmp_data$RecvInstructionsExecuted = rep(0,len)
      #}
      if (class(tmp_data) == "try-error") {
        cat("try-error reading file\n")
      }

         
      if (class(tmp_data) != "try-error") {
        file_count = file_count+1

        ## copy the data file
        #file.copy(paste(fullpath,file,sep="/"),paste(data_save_dir,file,sep="/"),overwrite=TRUE)
        len = length(tmp_data[,1]) # length of rows, not cols
        min_size = min(min_size, len)
        cat(data_subdir,'\t',i,'\t',len,'\t',data_ids[i],'\t',file,'\n')
        #tmp_data$name=rep(paste("Trace", sprintf("%02d",file_count)), len)
        tmp_data$name=rep(sprintf("%02d",file_count), len)
        
        #tmp_data$name=rep(substr(file,8, 9), len)
        
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
        
        
        #tmp_data$DTime = tmp_data$Time - tmp_data$SelfPathEditDistance 
        if (tmp_data$name != "NDSS") {
          #tmp_data$DTime = tmp_data$Time - tmp_data$ExecutionTreeTime - tmp_data$EditDistanceBuildTime
          #tmp_data$DTime = tmp_data$Time - tmp_data$EditDistanceBuildTime
          
          tmp_data$DTime = tmp_data$Time
        } else {
          tmp_data$DTime = tmp_data$Time
        }
        #v = c(tmp_data$DTime[1])
        v = c(0)
        
        for (j in seq(2,len)) {
          res = 0
          if (tsavg[j] < v[j-1]) {
            res = v[j-1] + tmp_data$DTime[j]
          } else {
            res = tsavg[j] + tmp_data$DTime[j]
          }
          v = append(v,res)
        }
        v = v - tsavg[seq(len)]
        tmp_data$Delay = v
        tmp_data$Game = tsavg[seq(len)]
        
        g = c()
        for (j in seq(len)) {
          g = append(g,floor(j/binwidth))
        }
        tmp_data$Bin = g
        
        #tmp_data = subset(tmp_data, Round < (len - 2))
        data = rbind(data, tmp_data)
        
        
      } else {
        cat("Error: ", data_subdir,'\t',i,'\n')
      }

    }
  }
}

time_vars=c("OtherTime","SolverTime","SearcherTime","ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime")

data$OtherTime = data$Time - data$SolverTime - data$ExecTreeTime - data$SearcherTime - data$MergeTime - data$EdDistTime - data$EdDistBuildTime - data$RebuildTime
data$OtherTime = ifelse(data$OtherTime < 0, 0, data$OtherTime)

# Compute the time not spent in ExecutionTree
#data$ExecTime = data$Time - data$ExecutionTreeTime
#data$TimeMinus = data$Time - data$TrainingTime - data$ExecutionTreeTime
#data$SendInstructionsExecuted = data$InstructionsExecuted - data$RecvInstructionsExecuted
#data$TimeMinus = data$Time - (data$EditDistanceComputeTime)*0.25
#data$ExecTime = data$Time - data$ExecutionTreeTime
#data$TimeMinus = data$Time - data$ExecutionTreeTime - data$EditDistanceBuildTime
data$TimeWOSolver = data$Time - data$SolverTime
#data$Time = data$Time - data$SelfPathEditDistance

###temp
#data = subset(data, name != "LOG 07" & name != "LOG 09" & name != "LOG 04")
#data = subset(data, name != "LOG 19" & name != "LOG 18")
#data = subset(data, name != "21")
#data = subset(data, mode != "nc-ed-row,1" & mode != "self-edit-dist-row,1")
#data = subset(data, name == "LOG 04" | name == "LOG 07")
#data = subset(data, name != "01" & name != "10" & name != "07")
#min_size = min_size - 10
start_round = 2

#min_size = max(data$Round)
#min_size = min_size - 5
legend_rows = ceiling(length(unique(factor(data$mode)))/3)

cat("start round: ",start_round,", min_size: ",min_size,"\n")

data = subset(data, (Round < min_size) & (Round > start_round))

plotwidth = default_plotwidth
plotheight = length(unique(data$name))*heightscalefactor
for (y_axis in plotnames) {
 x_axis = "Round"
 cat("plotting: (line), ",x_axis," vs ",y_axis,"\n")
 name = paste("plot","line",paste(x_axis,"vs",y_axis,sep=""),sep="_")
 title = paste(x_axis,"vs",y_axis, sep=" ")
 p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=x_axis, y=y_axis))
 
 p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5)
 #p = p + scale_fill_hue("Algorithm")
 p = p + facet_grid(name ~ .)
 #p = p + theme_bw()
 p = p + ylab(paste(y_axis,"(s)"))
 #p = p + scale_y_continuous(breaks=c(200,600,1000))
 #p = p + scale_y_continuous(breaks=c(500,1000,1500))
 p = p + scale_y_continuous()
 #p = p + cbgColourPalette
 p = p + theme(title=title,legend.position="bottom")
 p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
 p;  
 filename = paste(name, output_filetype, sep=".")
 ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
 
plotwidth = default_plotwidth
plotheight = length(unique(data$name))*heightscalefactor
for (y_axis in plotnames) {
 x_axis = "Round"
 cat("plotting (line, log scale): ",x_axis," vs ",y_axis,"\n")
 name = paste("plot","line","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
 title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
 p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=x_axis, y=y_axis))
 p = p + geom_point(aes(colour=factor(mode),linetype=factor(mode)),size=0.5)
 #p = p + stat_quantile(aes(colour=factor(mode),quantiles = 0.95))
 p = p + scale_y_log10() 
 p = p + theme_bw() 
 #p = p + cbgColourPalette
 p = p + facet_grid(name ~ .) 
 p = p + theme(title=title,legend.position="bottom")
 p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
 p;
 filename = paste(name, output_filetype, sep=".")
 ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

if (0) {
plotwidth = default_plotwidth
plotheight = length(unique(data$name))*heightscalefactor
for (y_axis in plotnames) {
  x_axis = "Round"
  cat("plotting (histogram, log scale): ",x_axis," vs ",y_axis,"\n")
  name = paste("plot","histogram","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=y_axis))
  p = p + geom_histogram() 
  p = p + scale_y_log10() 
  p = p + theme_bw() 
  #p = p + cbgColourPalette
  p = p + facet_grid(name ~ .) 
  p = p + theme(title=title,legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
}

plotwidth = default_plotwidth
plotheight = default_plotheight*2
for (y_axis in plotnames) {
  x_axis = "Round"
  name =  paste("plot","bar",y_axis,sep="_")
  cat("plotting (summary): ",x_axis," vs ",y_axis,"\n")
  title = paste("Summary of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x="mode", y=y_axis)) 

  p = p + theme_bw() 
  p = p + facet_grid(name ~ .)
  p = p + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray")
  #p = p + cbgColourPalette
  p = p + theme(title=title, axis.title.x=theme_blank(), axis.text.x=element_text(angle=-90))
  #p = p + theme(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

plotwidth = default_plotwidth
plotheight = default_plotheight*2
for (y_axis in plotnames) {
  x_axis = "Round"
  name =  paste("plot","mean_bar",y_axis,sep="_")
  cat("plotting (mean of): ",x_axis," vs ",y_axis,"\n")
  title = paste("Mean of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray") 
  p = p + theme_bw()
  p = p + facet_grid(name ~ .)
  #p = p + cbgColourPalette
  p = p + theme(title=title, axis.title.x=theme_blank(), axis.text.x=element_text(angle=-90))
  #p = p + theme(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

plotwidth = default_plotwidth*2
plotheight = default_plotheight
#for (y_axis in plotnames) {
  x_axis = "Round"
  name =  "time_summary"
  cat("plotting Time summary\n")
  title = paste("Time Summary")
  mdata <- melt(subset(data, Round < min_size & Round > start_round), id=c("STATS","Round","name","mode"),measure=time_vars)
  p <- ggplot(melt(cast(mdata, mode~variable, sum)),aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity", colour="white")
  p = p + theme_bw()
  #p = p + facet_grid(name ~ .)
  #p = p + cbgColourPalette
  p = p + ggtitle(title)
  p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  #p = p + theme(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
#}

if (0) {
plotwidth = default_plotwidth
plotheight = default_plotheight 
for (y_axis in plotnames) {
  x_axis = "Round"
  name =  paste("plot","boxplot_bar",y_axis,sep="_")
  cat("plotting (boxplot of): ",x_axis," vs ",y_axis,"\n")
  title = paste("Boxplot of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x="name", y=y_axis)) 
  #p <- ggplot(subset(data, Round < min_size & Round > start_round), aes(x=mode, y=Time, ymin = `0%`, lower = `25%`, middle = `50%`, upper = `75%`, ymax = `100%`)) 
  #p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray")
  
  p = p + scale_y_log10()
  #p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
  #                      labels = trans_format("log10", math_format(10^.x)))
  p = p + geom_boxplot(aes(colour=factor(mode),linetype=factor(mode)))
  
  #p = p + geom_boxplot(aes(colour=factor(mode),linetype=factor(mode)),outlier.size=1.0) + scale_fill_brewer(palette="OrRd")
  
  #p = p + scale_y_log10()
  #p = p + scale_x_discrete()
  #p = p + scale_y_continuous(trans = log_trans(10))
  
  #p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
  #                      labels = trans_format("log10", math_format(10^.x)))
  
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)
  
  #p = p + theme_bw()
  
  #p = p + facet_grid(. ~ name)
  #p = p + theme(legend.background = theme_rect(), legend.justification=c(0,1), legend.position=c(0,1), legend.title=theme_blank(), axis.title.x = theme_blank(), axis.text.x = theme_blank(), axis.ticks.x = theme_blank()) + ylab("Time (s)")
  #p = p + theme(axis.title.x = theme_blank(), axis.text.x = theme_blank(), axis.ticks.x = theme_blank()) + ylab("Time (s)")
 
  #p = p + ylab("Time (s)")
  #p = p + xlab("Trace")
  #p = p + theme(legend.position="none", axis.text.x=element_text(angle=45))
  
  #p = p + cbgColourPalette
  #p = p + theme(title=title, axis.title.x=theme_blank(), axis.text.x=element_text(angle=-90))
  #p = p + theme(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotwidth)
}

plotheight = default_plotheight 
special_plotnames = c("Delay")
for (y_axis in special_plotnames) {
  x_axis = "Bin"
  name =  paste("plot","special_boxplot_bar",y_axis,sep="_")
  cat("plotting (special boxplot of): ",x_axis," vs ",y_axis,"\n")
  title = paste("Boxplot of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(data, Round < min_size & Round > start_round), aes(x=factor(Bin), y=Delay)) 
  #p <- ggplot(subset(data, Round < min_size & Round > start_round), aes(x=mode, y=Time, ymin = `0%`, lower = `25%`, middle = `50%`, upper = `75%`, ymax = `100%`)) 
  #p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray")
  #p = p + geom_boxplot(aes(colour=factor(mode),linetype=factor(mode)))
  p = p + geom_boxplot()
  #p = p + geom_boxplot(outlier.size=1.0) #+ scale_fill_brewer(palette="OrRd")
  #p = p + stat_bin( geom="boxplot")
  #p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=2)
  #p = 
  #p = p + scale_y_log10()
  p = p + scale_x_discrete()
  #p = p + scale_y_continuous(trans = log_trans(10))
  #p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
  #                      labels = trans_format("log10", math_format(10^.x)))
  p = p + theme_bw()
  #p = p + facet_grid(. ~ name)
  #p = p + theme(legend.background = theme_rect(), legend.justification=c(0,1), legend.position=c(0,1), legend.title=theme_blank(), axis.title.x = theme_blank(), axis.text.x = theme_blank(), axis.ticks.x = theme_blank()) + ylab("Time (s)")
  #p = p + theme(axis.title.x = theme_blank(), axis.text.x = theme_blank(), axis.ticks.x = theme_blank()) + ylab("Time (s)")
  #p = p + theme(ylab("Time (s)")
  p = p + theme(legend.position="none")+ ylab("Delay (s)")

  #p = p + cbgColourPalette
  #p = p + theme(title=title, axis.title.x=theme_blank(), axis.text.x=element_text(angle=-90))
  #p = p + theme(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotwidth)
}
}
