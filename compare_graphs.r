#!/usr/bin/Rscript


## TODO: remove QueryConstructTime

args=commandArgs(trailingOnly=TRUE)

library(ggplot2)
library(plyr)
library(reshape)
library(scales)
library(quantreg)
library(multicore)

###############################################################################
### Configuration
###############################################################################

colnames = c(
  "Round",
  "Time","TimeReal","TimeSys",
  "SolverTime","SearcherTime","STPTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime",
  "Instructions","RecvInstructions",
  "StageCount", "CloneCount", "RemoveCount",
  "MergedStates","StateCount","TotalStates","Memory",
  "EditDist","EditDistK","EditDistMedoidCount",
  "EditDistSelfFirstMedoid","EditDistSelfLastMedoid",
  "EditDistSelfSocketEvent",
  "EditDistSocketEventFirstMedoid","EditDistSocketEventLastMedoid",
  "SocketEventSize", "ValidPathInstructions",
  "SymbolicVariableCount",
  "QueryCount","InvalidQueryCount","ValidQueryCount",
  "QueryCacheHits","QueryCacheMisses","QueryCounstructCount"
)

timeStats = c(
  "Time","TimeReal","TimeSys","AdjustedTime",
  "SolverTime","SearcherTime","STPTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime"
)

timestamp_colnames = c("MSGINFO","Timestamp","Direction","Bytes","SubBytes")

plotnames = c(
  "AdjustedTime",
  "ExtraInstructions",
  "SendInstructions",
  "Delay",
  colnames[c(-1)]
)

data_frame_col_names = c(colnames, "name", "mode", "Direction", "Delay")

root_dir="/home/rac/research/test.gsec/results/full/xpilot-ng-x11"
root_dir="/home/rac/research/test.gsec/results/full/tetrinet-klee"

# Read data file location from commandline or use hardcoded value
if (length(args) > 0) {
  root_dir = args[1]
}

data_dir="data"
output_dir="plots"
output_filetype="png"
timestamp_pattern = "*_client_socket.log"
timestamp_dir = paste(root_dir,"socketlogs",sep="/")

# Create output dirs
save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
dir.create(save_dir, recursive=TRUE)

# Plotting parameters
min_size=.Machine$integer.max
start_round = 2
binwidth=20
default_plotwidth=5
default_plotheight=5
heightscalefactor = 0.75

### Global Vars
timestamps <- NULL
all_data <- list()
modes <- list()
selected_modes = list()
data <- NULL

###############################################################################
### Read Timestamp data
###############################################################################

read_timestamps = function() {
  for (file in list.files(path=timestamp_dir,pattern=timestamp_pattern)) {
    # Read id number of timestamp file, format is str_#_...._client_socket.log
    
    name = as.integer(unlist(unlist(strsplit(file,"_"))[2]))
    
    tmp_timestamps = try(read.table(paste(timestamp_dir,file,sep="/"), col.names=timestamp_colnames), silent=TRUE)
    cat("Reading ",file,"\n")
    
    if (class(tmp_timestamps) == "try-error") {
      cat("try-error reading timestamp file\n")
    } else {
      
      # Remove first row
      tmp_timestamps = tmp_timestamps[c(-1),]
      
      len = length(tmp_timestamps[,1]) # length of rows, not cols
      tmp_timestamps$name=rep(name, len)
      tmp_timestamps$Round = seq(0,len-1)
      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp - rep(tmp_timestamps$Timestamp[1],len)
      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp * 1000000
      
      # Add timestamps to global var
      timestamps <<- rbind(timestamps, tmp_timestamps)
    }
  }
}

adjusted_time = function(df, i) {
  #return(df$TimeReal[i] - df$EdDistBuildTime[i] - df$STPTime[i])
  #return(df$TimeReal[i] - df$EdDistBuildTime[i] - df$SolverTime[i])
  return(df$TimeReal[i] - df$EdDistBuildTime[i])
}

compute_delays = function(m, name_id) {
  
  df = as.data.frame(m)
  colnames(df) = data_frame_col_names
  
  ts = subset(timestamps, name == name_id)
  
  df_len = length(df[,1])
  ts_len = length(ts[,1])
  
  len = min(df_len, ts_len)
  
  v = vector("numeric",len)
  v[1] = 0
  
  for (j in seq(2,len)) {
    #if (ts$Bytes[j] != df$SocketEventSize[j]) {
    #  cat("Bytes mismatch ",ts$Bytes[j]," ",df$SocketEventSize[j],"\n")
    #}
    
    if (ts$Timestamp[j] < v[j-1]) {
      v[j] = v[j-1] + adjusted_time(df,j)
    } else {
      v[j] = ts$Timestamp[j] + adjusted_time(df,j)
    }
    
    #delta = v[j] - v[j-1]
    #if (delta > 500) {
    #  cat("Large delta ",delta," at round ", j,"\n")
    #}
  }
  v = v - ts$Timestamp[seq(len)]

  rm(df)
  rm(ts)

  return(v)
}

###############################################################################
### Read data files
###############################################################################

get_mode_id = function(mode_str) {  
  if(length(modes) > 0) {
    for (id in seq(length(modes))) {
      if (modes[[id]] == mode_str) {
        return (id)
      }
    }
  }
  modes[[length(modes) + 1]] <<- mode_str
  return(length(modes))
}

read_data_subdir = function(data_mode_dir, data_date_dir, mode_id) {

  data_path = paste(root_dir, data_dir, data_mode_dir, data_date_dir, sep="/")
  
  for (file in list.files(path=data_path)) {
    file_name = paste(data_path,file,sep="/")
    
    # Read number of lines in file
    nrows = as.integer(unlist(unlist(strsplit(system(paste("wc -l ", file_name, sep=""), intern=T)," "))[1]))
    ncols = length(colnames)
    
    # Read file
    #tmp_data = try(read.table(file_name, col.names=colnames, nrows=nrows,sep=" ",colClasses="numeric",comment.char=""), silent=TRUE)
    tmp_data = try(matrix(scan(file_name,what=integer(),nmax=nrows*ncols,quiet=TRUE),nrow=nrows,ncol=ncols,byrow=TRUE), silent=TRUE)
    
    if (class(tmp_data) != "try-error") {
      
      # length of rows, not cols
      len = length(tmp_data[,1]) 
      
      # extract file id
      id = as.integer(unlist(unlist(strsplit(file,"_|\\."))[2]))
      
      cat(data_mode_dir,'\t',len,'\t',data_date_dir,'\t',file,'\t',id,'\n')
      
      # Add Name id 
      tmp_data = cbind(tmp_data, rep(id, len))
      
      # Add Mode id
      tmp_data = cbind(tmp_data, rep(mode_id, len))
              
      tmp_data = cbind(tmp_data, rep(0, len))
      tmp_data = cbind(tmp_data, rep(0, len))
      #tmp_data = cbind(tmp_data, rep(0, len))
      
      # Compute delay values
      if (length(subset(timestamps, name == id)[,1]) > 0) {
        delays = compute_delays(tmp_data, id)
        delays_len = length(delays)
        tmp_data = tmp_data[seq(delays_len), ]
        cols = length(tmp_data[1,])
        tmp_data[,cols] = delays
        
        tmp_data = cbind(tmp_data, delays)
      } else {
        cat("not computing delays\n")
        tmp_data = cbind(tmp_data, rep(0, len))
      }

      # Set bin number
      #g = c()
      #for (j in seq(len)) { g = append(g,floor(j/binwidth)) }
      #tmp_data$Bin = g
            
      all_data[[length(all_data) + 1]] <<- tmp_data
      
    } else {
      cat("Error: ", file_name,'\n')
    }
  }
}

read_all_data = function() {
  
  for (data_mode_dir in dir(paste(root_dir,data_dir,sep="/"), full.names=FALSE, recursive=FALSE)) {
    
    data_path = paste(root_dir, data_dir, data_mode_dir, sep="/")
    
    data_date_dirs = sort(dir(data_path, full.names=FALSE, recursive=FALSE), decreasing=TRUE)
    
    if (length(selected_modes) == 0 | data_mode_dir %in% selected_modes) {
      for (data_date_dir in data_date_dirs[seq(1)]) {
        mode_id = get_mode_id(data_mode_dir)
        read_data_subdir(data_mode_dir, data_date_dir, mode_id)
      }
    }
  }
}



###############################################################################
### Plot Functions 
###############################################################################

### Jittered point plot of data
do_point_plot = function(y_axis) {
  cat("plotting: (point), ",x_axis," vs ",y_axis,"\n")
 
  # remove zero values
  mdata = data[match.fun('!=')(data[[y_axis]], 0), ]
  
  if (length(mdata[,1]) == 0)
    return
  
  # vars
  name = paste("plot","point",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  filename = paste(name, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  p = p + geom_jitter(aes(colour=factor(mode),linetype=factor(mode)),size=1)
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
 
  # remove zero values
  #mdata = data[match.fun('!=')(data[[y_axis]], 0), ]
  
  #if (length(mdata[,1]) == 0)
  #  return
  
  # vars
  name = paste("plot","line",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  filename = paste(name, output_filetype, sep=".")
 
  # construct plot
  #p = ggplot(mdata, aes_string(x=x_axis, y=y_axis))
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  #p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
  p = p + geom_line(aes(colour=factor(mode)),size=0.5)
  p = p + facet_grid(name ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  #p = p + scale_y_continuous(breaks=c(200,600,1000))
  #p = p + scale_y_continuous(breaks=c(500,1000,1500))
  p = p + scale_y_continuous()
  p = p + ggtitle(title) + theme(legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows))
                    
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
  #p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
  p = p + geom_line(aes(colour=factor(mode)),size=0.5)
  p = p + facet_grid(name ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_log10() 
  p = p + ggtitle(title) + theme(legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows))
  
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
  cat("Reformatting data\n")
  #mdata <- melt(data, id=c("Round","name","mode"),measure=graphTimeStats)
  mdata <- melt(data, id=c("mode"),measure=graphTimeStats)

  # construct plot
  cat("Constructing plot\n")
  p <- ggplot(melt(cast(mdata, mode~variable, sum)),aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity") + theme_bw()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))

  p;
  ggsave(paste(save_dir, filename, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
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

print_round = function(mdata,round) {
  rdata = mdata[match.fun("==")(mdata[["Round"]], round), ]
  len = max(nchar(colnames))
  for (stat in  colnames[c(-1,-2)]) {
    v = rdata[[stat]]
    #if (v > 0) {
      s = sprintf("%-32s %4.2f", stat, v)
      cat(s, "\n")
    #}
  }
}

###############################################################################
###############################################################################

client_type = rev(strsplit(root_dir,"/")[[1]])[1]
num_threads=4

if (client_type == "tetrinet-klee") {
  selected_modes = c("nc-4096-64-8", "ch-4096-64", "self", "nc-4096-64-8-t","ch-4096-64-t","self-t")
  num_threads=4
} else if (client_type == "xpilot-ng-x11") {
  selected_modes = c("nc-4096-128-16", "ch-4096-128", "self", "nc-4096-128-16-t","ch-4096-128-t","self-t")
  num_threads=2
}

# Read the timestamp data
read_timestamps()

# Read cliver logs
read_all_data()

# Convert list of data matrices to a single data frame
data = as.data.frame(do.call(rbind, all_data))
rm(all_data)
colnames(data) = data_frame_col_names
# Rename integer factors to string names
for (i in seq(length(modes))) {
  data$mode[data$mode == i] <- modes[[i]]
}

# Compute additional stats
data$ExtraInstructions = data$Instructions - data$ValidPathInstructions
data$SendInstructions = data$Instructions - data$RecvInstructions
data$AdjustedTime = data$TimeReal - data$EdDistBuildTime
data$SolverTime = data$SolverTime - data$STPTime - data$CEXTime

# Remove round times from list of time stats to graph
graphTimeStats = timeStats[c(-1,-2,-3,-4)]

### Compute OtherTime
otherTime = data$TimeReal + data$TimeSys
for (t in graphTimeStats) {
  otherTime = otherTime - data[t]
}
data$OtherTime = otherTime

# Add other time list of time variables
timeStats = c(timeStats, "OtherTime")

# Scale time stats from microsecnds to seconds
for (tstat in c(timeStats,"Delay")) {
  data[tstat] = data[tstat] / 1000000.0
}

# Trim data by start and min rounds 
data = subset(data, Round > start_round)

###############################################################################

x_axis = "Round"

#data = subset(data, mode == "nc-4096-64-8" | mode == "ch-4096-64" | mode == "self")
#data = subset(data, name != "09" & name != "10")
#data = subset(data, name != 9 & name != 10)
#data = subset(data, name != 0 & name != 7)

plotwidth = default_plotwidth
plotheight = default_plotheight

legend_rows = ceiling(length(unique(factor(data$mode)))/3)

#invisible(gc(reset=TRUE))

# Remove empty stats from plot list
new_plotnames = NULL
for (p in plotnames) {
  if (max(data[[p]]) != 0 | min(data[[p]]) != 0) {
    new_plotnames = c(new_plotnames, p)
  }
}
plotnames = new_plotnames

do_time_summary_plot()

plotheight = length(unique(data$name))*heightscalefactor

results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_logscale_line_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_point_plot, mc.cores=num_threads)

plotheight = default_plotheight*2

results = mclapply(c("Delay"), do_max_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_histogram_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_summary_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_mean_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)

###############################################################################
