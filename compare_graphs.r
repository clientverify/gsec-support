#!/usr/bin/Rscript

args=commandArgs(trailingOnly=TRUE)

library(ggplot2)
library(reshape)
library(scales)
library(quantreg)

# cbgColourPalette <- scale_colour_manual(values=c("#999999", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"))
cbgColourPalette <- scale_colour_manual(values=c("#0072B2", "#56B4E9", "#E69F00", "#009E73", "#F0E442", "#999999", "#D55E00", "#CC79A7"))

colnames = c(
  "STATS","Round",
  "Time","TimeReal","TimeSys",
  "SolverTime","SearcherTime","QueryTime","CEXTime","QueryConstructTime","ResolveTime",
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
  "SolverTime","SearcherTime","QueryTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime"
)

timestamp_colnames = c("MSGINFO","Timestamp","Direction","Bytes","SubBytes")

plotnames = c(
  "Time",
  "Instructions", 
  "Memory", 
  "EditDist",
  "EditDistK",
  "Delay",
  "ExtraInstructions",
  "SendInstructions"
)
plotnames = c(
  "Delay",
  "ExtraInstructions",
  "SendInstructions"
)
plotnames=c(plotnames, colnames[c(-1,-2)])

default_plotwidth=5
default_plotheight=5
heightscalefactor = 1.0

#root_dir="/home/rac/research/gsec/results.oakall/xpilot-ng-x11"
#root_dir="/home/rac/research/test.gsec/results/cr/xpilot-ng-x11"
#root_dir="/home/rac/research/test.gsec/results/tetrinet-klee"

root_dir="/home/rac/research/test.gsec/results/meeting/xpilot-ng-x11"

timestamp_dir="/home/rac/research/test.gsec/data/network/xpilot-game/large-fps25"

if (length(args) > 0) {
  root_dir = args[1]
}

data_dir="data"
output_dir="plots"
output_filetype="png"

#create output dirs
save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
dir.create(save_dir, recursive=TRUE)

min_size=.Machine$integer.max
data = NULL

previous_count = 1
binwidth=20


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

#Adjust time stats
for (tstat in timeStats) {
 data[tstat] = data[tstat] / 1000000
}


timestamp_pattern = "*_client_socket.log"
timestamps = NULL

for (file in list.files(path=timestamp_dir,pattern=timestamp_pattern)) {
  #x = unlist(strsplit(file,timestamp_pattern)[1])
  #cat(x,"\n")
  id = unlist(unlist(strsplit(file,"_"))[2])
  #cat(id,"\n")
  tmp_timestamps = try(read.table(paste(timestamp_dir,file,sep="/"), col.names=timestamp_colnames), silent=TRUE)
  if (class(tmp_timestamps) == "try-error") {
    cat("try-error reading timestamp file\n")
  }
  
  # Remove first row
  tmp_timestamps = tmp_timestamps[c(-1),]
  
  len = length(tmp_timestamps[,1]) # length of rows, not cols
  tname = sprintf("%02d",as.integer(id))
  tmp_timestamps$name=rep(tname, len)
  tmp_timestamps$Round = seq(0,len-1)
  tmp_timestamps$Timestamp = tmp_timestamps$Timestamp - rep(tmp_timestamps$Timestamp[1],len)
  #tmp_timestamps$Timestamp = tmp_timestamps$Timestamp * 1000000 # convert to microseconds
  
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
           res = v[j-1] + (sdata$Time[j] - sdata$EdDistBuildTime[j])
         } else {
           res = tmp_timestamps$Timestamp[j] + (sdata$Time[j] - sdata$EdDistBuildTime[j])
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

for (n in unique(factor(data$name))) {
  count = length(unique(factor(data$mode)))
  tmp = subset(data, name == n)
  for (m in unique(factor(data$mode))) {
    if (length(subset(tmp,mode == m)) > 0) {
      count = count - 1
    }
  }
}

#data$SolverTime = data$SolverTime - data$QueryTime - data$CEXTime - data$QueryConstructTime

time_vars=c("OtherTime","SolverTime","SearcherTime","ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime","QueryTime","CEXTime","QueryConstructTime","ResolveTime")

data$OtherTime = data$Time - data$SolverTime - data$ExecTreeTime - data$SearcherTime - data$MergeTime - data$EdDistTime - data$EdDistBuildTime - data$RebuildTime - data$QueryTime - data$CEXTime - data$QueryConstructTime - data$ResolveTime
#data$OtherTime = data$Time - data$SolverTime - data$ExecTreeTime - data$SearcherTime - data$MergeTime - data$EdDistTime - data$EdDistBuildTime
#data$OtherTime = ifelse(data$OtherTime < 0, 0, data$OtherTime)

data$ExtraInstructions = data$Instructions - data$ValidPathInstructions

data$SendInstructions = data$Instructions - data$RecvInstructions

###temp
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
  cat("plotting: (point), ",x_axis," vs ",y_axis,"\n")
  name = paste("plot","point",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=x_axis, y=y_axis))
  
  p = p + geom_point(aes(colour=factor(mode),shape=factor(mode)))
  #p = p + scale_fill_hue("Algorithm")
  p = p + facet_grid(name ~ .)
  p = p + theme_bw()
  p = p + ylab(paste(y_axis,"(s)"))
  #p = p + scale_y_continuous(breaks=c(200,600,1000))
  #p = p + scale_y_continuous(breaks=c(500,1000,1500))
  p = p + scale_y_continuous()
  #p = p + cbgColourPalette
  p = p + ggtitle(title)
  p = p + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  
  p;  
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
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
 p = p + theme_bw()
 p = p + ylab(paste(y_axis,"(s)"))
 #p = p + scale_y_continuous(breaks=c(200,600,1000))
 #p = p + scale_y_continuous(breaks=c(500,1000,1500))
 p = p + scale_y_continuous()
 #p = p + cbgColourPalette
 p = p + ggtitle(title)
 p = p + theme(legend.position="bottom")
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
  p = p + ggtitle(title)
  p = p + theme(legend.position="bottom")
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
  p = p + ggtitle(title)
  p = p + theme(axis.title.x=theme_blank(), axis.text.x=element_text(angle=-90))
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
  p = p + ggtitle(title)
  p = p + theme(axis.title.x=theme_blank(), axis.text.x=element_text(angle=-90))
  #p = p + theme(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}

plotwidth = default_plotwidth
plotheight = default_plotheight*2
  x_axis = "Round"
  y_axis = "Delay"
  tdata = data
  tdata$Delay = tdata$Delay / (1000000*60)
  name =  paste("plot","max",y_axis,sep="_")
  cat("plotting (mean of): ",x_axis," vs ",y_axis,"\n")
  title = paste("Max of",y_axis,"over",min_size,"rounds",sep=" ")
  p <- ggplot(subset(tdata, Round < min_size & Round > start_round), aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="max", geom="bar", fill="white", colour="gray") 
  p = p + theme_bw()
  p = p + facet_grid(name ~ .)
  #p = p + cbgColourPalette
  p = p + ggtitle(title)
  p = p + theme(axis.title.x=theme_blank(), axis.text.x=element_text(angle=-90))
  #p = p + theme(title=title,legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = 2), linetype = guide_legend(title=NULL, nrow = 2))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)

plotwidth = default_plotwidth*2
plotheight = default_plotheight
#for (y_axis in plotnames) {
  x_axis = "Round"
  name =  "time_summary"
  cat("plotting Time summary\n")
  title = paste("Time Summary")
  mdata <- melt(subset(data, Round < min_size & Round > start_round), id=c("STATS","Round","name","mode"),measure=time_vars)
  p <- ggplot(melt(cast(mdata, mode~variable, sum)),aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity")
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

plotwidth = default_plotwidth
plotheight = length(unique(data$name))*heightscalefactor
for (y_axis in plotnames) {
  x_axis = "Round"
  cat("plotting (line, log scale): ",x_axis," vs ",y_axis,"\n")
  name = paste("plot","line","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  p = ggplot(subset(data, Round < min_size & Round > start_round), aes_string(x=x_axis, y=y_axis))
  p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5)
  #p = p + stat_quantile(aes(colour=factor(mode),quantiles = 0.95))
  p = p + scale_y_log10() 
  p = p + theme_bw() 
  #p = p + cbgColourPalette
  p = p + facet_grid(name ~ .) 
  p = p + ggtitle(title)
  p = p + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p;
  filename = paste(name, output_filetype, sep=".")
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
}
