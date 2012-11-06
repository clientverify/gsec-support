#!/usr/bin/Rscript


## TODO: remove QueryConstructTime

args=commandArgs(trailingOnly=TRUE)

library(ggplot2)
library(reshape)
library(scales)
library(quantreg)
library(multicore)

###############################################################################
### Configuration
###############################################################################

colnames = c(
  "STATS","Round",
  "Time","TimeReal","TimeSys",
  "SolverTime","SearcherTime","STPTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime",
  "Instructions","RecvInstructions",
  "StageCount","MergedStates","StateCount","TotalStates","Memory",
  "EditDist","EditDistK","EditDistMedoidCount","EditDistClosestMedoid",
  "SocketEventSize", "ValidPathInstructions",
  "QueryCount","InvalidQueryCount","ValidQueryCount",
  "QueryCacheHits","QueryCacheMisses","QueryCounstructCount"
)

timeStats = c(
  "Time","TimeReal","TimeSys",
  "SolverTime","SearcherTime","STPTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime"
)

timestamp_colnames = c("MSGINFO","Timestamp","Direction","Bytes","SubBytes")

plotnames = c(
  "AdjustedTime",
  "Delay",
  "ExtraInstructions",
  "SendInstructions"
)
plotnames=c(plotnames, colnames[c(-1,-2)])

default_plotwidth=5
default_plotheight=5
heightscalefactor = 1.0

root_dir="/home/rac/research/test.gsec/results/cr.2/xpilot-ng-x11"

# Read data file location from commandline or use hardcoded value
if (length(args) > 0) {
  root_dir = args[1]
}

data_dir="data"
output_dir="plots"
output_filetype="png"

# Create output dirs
save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
dir.create(save_dir, recursive=TRUE)

min_size=.Machine$integer.max
data = NULL

previous_count = 1
binwidth=20

###############################################################################
### Read data files
###############################################################################

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
        cat("try-error reading file\n")
      }
      
      if (class(tmp_data) != "try-error") {
        file_count = file_count+1
        
        len = length(tmp_data[,1]) # length of rows, not cols
        min_size = min(min_size, len)
        cat(data_subdir,'\t',i,'\t',len,'\t',data_ids[i],'\t',file,'\n')
        
        tmp_data$name=rep(sprintf("%02d",file_count), len)
        
        tmp_data$Game=rep(0, len)
        tmp_data$Delay=rep(0, len)
        
        # Set mode description based on parent dir
        if (previous_count > 1) {
          tmp_data$mode=rep(paste(data_subdir,i,sep=","), len)
        } else {
          tmp_data$mode=rep(data_subdir, len)
        }
        
        # Set bin number
        g = c()
        for (j in seq(len)) {
          g = append(g,floor(j/binwidth))
        }
        tmp_data$Bin = g
        
        data = rbind(data, tmp_data)
        
      } else {
        cat("Error: ", data_subdir,'\t',i,'\n')
      }
      
    }
  }
}

# Compute additional stats
data$ExtraInstructions = data$Instructions - data$ValidPathInstructions
data$SendInstructions = data$Instructions - data$RecvInstructions
data$AdjustedTime = data$Time - data$EdDistBuildTime

###############################################################################
### Read Timestamp data
###############################################################################

# Scale time stats from microsecnds to seconds
for (tstat in timeStats) {
 data[tstat] = data[tstat] / 1000000
}

### 
timestamp_pattern = "*_client_socket.log"
timestamps = NULL
timestamp_dir = paste(root_dir,"socketlogs",sep="/")

for (file in list.files(path=timestamp_dir,pattern=timestamp_pattern)) {
  # Read id number of timestamp file, format is str_#_...._client_socket.log
  id = unlist(unlist(strsplit(file,"_"))[2])
  tmp_timestamps = try(read.table(paste(timestamp_dir,file,sep="/"), col.names=timestamp_colnames), silent=TRUE)

  if (class(tmp_timestamps) == "try-error") {
    cat("try-error reading timestamp file\n")
  } else {
    
    # Remove first row
    tmp_timestamps = tmp_timestamps[c(-1),]
    
    len = length(tmp_timestamps[,1]) # length of rows, not cols
    tname = sprintf("%02d",as.integer(id))
    tmp_timestamps$name=rep(tname, len)
    tmp_timestamps$Round = seq(0,len-1)
    tmp_timestamps$Timestamp = tmp_timestamps$Timestamp - rep(tmp_timestamps$Timestamp[1],len)
    
    for (tmode in unique(factor(data$mode))) {
      sdata = subset(data, name == tname & mode == tmode)
      
      # Remove sdata from data
      data = subset(data, !(name == tname & mode == tmode))
      
      sdata = subset(sdata, Round < 2000)
      
      tlen = length(sdata[,1]) # length of rows, not cols
    
      cat("Computing Timestamps for: ",tname," ",tmode," tlen=",tlen,", len=",len,"\n")
      if (len > tlen & tlen > 0) {
        v = c(0)
    
        for (j in seq(2,tlen)) {
          res = 0
          if (tmp_timestamps$Timestamp[j] < v[j-1]) {
            res = v[j-1] + sdata$AdjustedTime[j]
          } else {
            res = tmp_timestamps$Timestamp[j] + sdata$AdjustedTime[j]
          }
          v = append(v,res)
        }
        v = v - tmp_timestamps$Timestamp[seq(tlen)]
        sdata$Delay = v
        sdata$Game = tmp_timestamps$Timestamp[seq(tlen)]
        
        data = rbind(data,sdata)
        
      } else {
        cat("ERROR Tlen is less than len ",tname," ",tmode," tlen=",tlen,", len=",len,"\n")
      }
      
    }
    
    timestamps = rbind(timestamps, tmp_timestamps)
  }
}

for (n in unique(factor(data$name))) {
  count = length(unique(factor(data$mode)))
  tmp = subset(data, name == n)
  for (m in unique(factor(data$mode))) {
    if (length(subset(tmp,mode == m)) > 0) {
      count = count - 1
    }
  }
}

###############################################################################
### Reformat data 
###############################################################################

data$SolverTime = data$SolverTime - data$STPTime - data$CEXTime

# Remove round times
graphTimeStats = timeStats[c(-1,-2,-3)]

### Compute OtherTime
otherTime = data$TimeReal + data$TimeSys
for (t in graphTimeStats) {
  otherTime = otherTime - data[t]
}
data$OtherTime = otherTime

# Add other time list of time variables
timeStats = c(timeStats, "OtherTime")

# Plotting parameters
start_round = 2
legend_rows = ceiling(length(unique(factor(data$mode)))/3)

# Trim data by start and min rounds 
data = subset(data, Round < min_size & Round > start_round)

###############################################################################
### Plot Functions 
###############################################################################

### Jittered point plot of data
do_point_plot = function(y_axis) {
  cat("plotting: (point), ",x_axis," vs ",y_axis,"\n")
 
  # vars
  name = paste("plot","point",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  filename = paste(name, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  p = p + geom_jitter(aes(colour=factor(mode),linetype=factor(mode)),size=0.25)
  p = p + facet_grid(name ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_continuous()
  p = p + ggtitle(title) + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  
  p;  
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
 
### Line plot of data
do_line_plot = function(y_axis) {
  cat("plotting: (line), ",x_axis," vs ",y_axis,"\n")
 
  # vars
  name = paste("plot","line",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  filename = paste(name, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
  p = p + facet_grid(name ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  #p = p + scale_y_continuous(breaks=c(200,600,1000))
  #p = p + scale_y_continuous(breaks=c(500,1000,1500))
  p = p + scale_y_continuous()
  p = p + ggtitle(title) + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  
  p;  
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

### Logscale line plot of data
do_logscale_line_plot = function(y_axis) {
  cat("plotting (line, log scale): ",x_axis," vs ",y_axis,"\n")
 
  # vars
  name = paste("plot","line","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  filename = paste(name, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
  p = p + facet_grid(name ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_log10() 
  p = p + ggtitle(title) + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  
  p;  
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

### Histogram of data
do_histogram_plot = function(y_axis) {
  cat("plotting (histogram, log scale): ",x_axis," vs ",y_axis,"\n")

  # vars
  name = paste("plot","histogram","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  filename = paste(name, output_filetype, sep=".")

  # construct plot
  p = ggplot(data, aes_string(x=y_axis))
  p = p + geom_histogram() 
  p = p + scale_y_log10() + theme_bw() + facet_grid(name ~ .) 
  p = p + ggtitle(title) + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))

  p;
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

### Summary of data in bar plot
do_summary_plot = function(y_axis) {
  cat("plotting (summary): ",x_axis," vs ",y_axis,"\n")

  # vars
  name =  paste("plot","bar",y_axis,sep="_")
  title = paste("Summary of",y_axis,"over",min_size,"rounds",sep=" ")
  filename = paste(name, output_filetype, sep=".")

  # construct plot
  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + facet_grid(name ~ .) + theme_bw()
  p = p + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray")
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p;
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

### Mean summary plot
do_mean_plot = function(y_axis) {
  cat("plotting (mean of): ",x_axis," vs ",y_axis,"\n")

  name =  paste("plot","mean_bar",y_axis,sep="_")
  title = paste("Mean of",y_axis,"over",min_size,"rounds",sep=" ")
  filename = paste(name, output_filetype, sep=".")

  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray") 
  p = p + facet_grid(name ~ .) + theme_bw()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p;
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

### Max summary plot
do_max_plot = function(y_axis) {
  cat("plotting (max of): ",x_axis," vs ",y_axis,"\n")

  name =  paste("plot","max_bar",y_axis,sep="_")
  title = paste("max of",y_axis,"over",min_size,"rounds",sep=" ")
  filename = paste(name, output_filetype, sep=".")

  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="max", geom="bar", fill="white", colour="gray") 
  p = p + facet_grid(name ~ .) + theme_bw()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p;
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

### Time summary plot
do_time_summary_plot = function() {
  cat("plotting Time summary\n")

  name =  "time_summary"
  title = paste("Time Summary")
  filename = paste(name, output_filetype, sep=".")

  # reformat data
  mdata <- melt(data, id=c("STATS","Round","name","mode"),measure=graphTimeStats)

  # construct plot
  p <- ggplot(melt(cast(mdata, mode~variable, sum)),aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity") + theme_bw()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))

  p;
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

### Boxplot
do_box_plot = function(y_axis) {
  cat("plotting (boxplot of): ",x_axis," vs ",y_axis,"\n")

  # vars
  name =  paste("plot","boxplot_bar",y_axis,sep="_")
  title = paste("Boxplot of",y_axis,"over",min_size,"rounds",sep=" ")
  filename = paste(name, output_filetype, sep=".")

  # construct plot
  p <- ggplot(data, aes_string(x="name", y=y_axis)) 
  p = p + scale_y_log10()
  p = p + geom_boxplot(aes(colour=factor(mode),linetype=factor(mode)))
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)
  
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotwidth)
}

###############################################################################

x_axis = "Round"

plotwidth = default_plotwidth
plotheight = default_plotheight

do_time_summary_plot()

plotheight = length(unique(data$name))*heightscalefactor

mclapply(plotnames, do_line_plot)
#mclapply(plotnames, do_logscale_line_plot)
mclapply(plotnames, do_point_plot)

plotheight = default_plotheight*2

#mclapply(plotnames, do_histogram_plot)
#mclapply(plotnames, do_summary_plot)
mclapply(plotnames, do_mean_plot)
mclapply(c("Delay"), do_max_plot)

plotheight = default_plotheight*2

mclapply(plotnames, do_box_plot)

exit

###############################################################################

if (0) {
plotwidth = default_plotwidth
plotheight = default_plotheight 
for (y_axis in plotnames) {
  x_axis = "Round"
  name =  paste("plot","boxplot_bar",y_axis,sep="_")
  cat("plotting (boxplot of): ",x_axis," vs ",y_axis,"\n")
  title = paste("Boxplot of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(data, aes_string(x="name", y=y_axis)) 
  #p <- ggplot(data, aes(x=mode, y=Time, ymin = `0%`, lower = `25%`, middle = `50%`, upper = `75%`, ymax = `100%`)) 
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
  p <- ggplot(data, aes(x=factor(Bin), y=Delay)) 
  #p <- ggplot(data, aes(x=mode, y=Time, ymin = `0%`, lower = `25%`, middle = `50%`, upper = `75%`, ymax = `100%`)) 
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

