#!/usr/bin/Rscript

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
  "Message",
  "TimeFull","TimeReal","TimeSys",
  "SolverTime","SearcherTime","STPTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime","EdDistHintTime", "EdDistStatTime",
  "MergeTime","RebuildTime",
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
  "TimeFull","TimeReal","TimeSys","Time",
  "SolverTime","SearcherTime","STPTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime","MergeTime","RebuildTime"
)

timestamp_colnames = c("MSGINFO","Timestamp","Direction","Bytes","SubBytes")

plotnames = c(
  #colnames[c(-1)],
  "Time",
  "EditDistMedoidCount",
  #"ExtraInstructions",
  #"SendInstructions",
  "Delay"
)

data_frame_col_names = c(colnames, "trace", "mode", "Direction", "Bin", "Delay")

#root_dir="/home/rac/research/test.gsec/results/fast.2/xpilot-ng-x11"
root_dir="/home/rac/research/test.gsec/results/fast.2/tetrinet-klee"

# Read data file location from commandline or use hardcoded value
if (length(args) > 0) {
  root_dir = args[1]
}
cat("Rootdir: ", root_dir, "\n")

data_dir="data"
output_dir="plots"
output_filetype="eps"
timestamp_pattern = "*_client_socket.log"
timestamp_dir = paste(root_dir,"socketlogs",sep="/")

# Create output dirs
save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
dir.create(save_dir, recursive=TRUE)

# Plotting parameters
min_size=.Machine$integer.max
start_Message = 2
binwidth=20
default_plotwidth=6
default_plotheight=6
heightscalefactor = 0.75
heightscalefactor = 0.5
plotwidth = default_plotwidth
plotheight = default_plotheight

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
    
    trace = as.integer(unlist(unlist(strsplit(file,"_"))[2]))
    
    tmp_timestamps = try(read.table(paste(timestamp_dir,file,sep="/"), col.names=timestamp_colnames), silent=TRUE)
    cat("Reading ",file,", trace: ",trace, "\n")
    
    if (class(tmp_timestamps) == "try-error") {
      cat("try-error reading timestamp file\n")
    } else {
      
      # Remove first row
      tmp_timestamps = tmp_timestamps[c(-1),]
      
      len = length(tmp_timestamps[,1]) # length of rows, not cols
      tmp_timestamps$trace=rep(trace, len)
      tmp_timestamps$Message = seq(0,len-1)
      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp - rep(tmp_timestamps$Timestamp[1],len)
      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp * 1000000

     # Add timestamps to global var
      timestamps <<- rbind(timestamps, tmp_timestamps)
    }
  }
}

adjusted_time = function(df, i) {
  return(df$TimeReal[i] - df$EdDistHintTime[i] - df$EdDistStatTime[i])
}

compute_delays = function(m, trace_id) {
  df = as.data.frame(m)
  colnames(df) = data_frame_col_names
  
  ts = subset(timestamps, trace == trace_id)
  
  df_len = length(df[,1])
  ts_len = length(ts[,1])
  
  len = min(df_len, ts_len)
  
  #cat("Computing Delays for ", trace_id," dflen=",df_len," tslen=",ts_len," len=", len,"\n")
  
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
    
    delta = v[j] - v[j-1]
    if (delta > 200*1000000) {
     cat("Large delta ",delta," at Message ", j,"\n")
    }
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

get_mode_str = function(mode_id) {  
  if (length(selected_modes) == 0) {
    return(modes[[mode_id]])
  } else {
    for (id in seq(length(selected_modes))) {
      if (modes[[mode_id]] == selected_modes[[id]]) {
        return (selected_modes_alt_names[[id]])
      }
    }
  }
  return("error")
}

read_data_subdir = function(data_mode_dir, data_date_dir, mode_id) {

  data_path = paste(root_dir, data_dir, data_mode_dir, data_date_dir, sep="/")
  
  for (file in list.files(path=data_path)) {
    file_name = paste(data_path,file,sep="/")
    
    # Read number of lines in file
    nrows = as.integer(unlist(unlist(strsplit(system(paste("wc -l ", file_name, sep=""), intern=T)," "))[1]))
    ncols = length(colnames)
    
    # Read file
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
              
      # Add Direction
      ts = subset(timestamps, trace == id)
      directions = as.integer(factor(ts$Direction))

      if (length(directions) < len) {
        directions = c(directions, rep(0, len - length(directions)))
      }
      tmp_data = cbind(tmp_data, directions[seq(len)])

      # Set bin number
      g = c()
      for (j in seq(len)) { g = append(g,binwidth*(floor(j/binwidth))) }
      tmp_data = cbind(tmp_data, g)
      
      # Add placeholder for Delay
      tmp_data = cbind(tmp_data, rep(0, len))

      # Compute delay values
      if (length(subset(timestamps, trace == id)[,1]) > 0) {
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

      if (min_size > length(tmp_data[,1])) {
        min_size <<- length(tmp_data[,1])
      }
           
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
  trace = paste(client_type,"point",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  p = p + geom_jitter(aes(colour=factor(mode),linetype=factor(mode)),size=1)
  p = p + facet_grid(trace ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_continuous()
  p = p + ggtitle(title) + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  
  p;  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}
 
### Line plot of data
do_line_plot = function(y_axis) {
  cat("plotting: (line), ",x_axis," vs ",y_axis,"\n")
 
  # remove zero values
  #mdata = data[match.fun('!=')(data[[y_axis]], 0), ]
  #if (length(mdata[,1]) == 0)
  #  return
  
  # vars
  trace = paste(client_type,"line",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # construct plot
  #p = ggplot(mdata, aes_string(x=x_axis, y=y_axis))
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  #p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
  p = p + geom_line(aes(colour=factor(mode)),size=0.5)
  p = p + facet_grid(trace ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_continuous()
  p = p + ggtitle(title) + theme(legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows))
                    
  p;  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Alt. Line plot of data
do_line_alt_plot = function(y_axis) {
  cat("plotting: (alt line), ",x_axis," vs ",y_axis,"\n")
 
  # vars
  trace = paste(client_type,"line","alt",paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  p = p + geom_jitter(size=1)
  p = p + facet_grid(mode ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_continuous()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
                    
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}


### Logscale line plot of data
do_logscale_line_plot = function(y_axis) {
  cat("plotting (line, log scale): ",x_axis," vs ",y_axis,"\n")
 
  # vars
  trace = paste(client_type,"line","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  #p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
  p = p + geom_line(aes(colour=factor(mode)),size=0.5)
  p = p + facet_grid(trace ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)))
  p = p + ggtitle(title) + theme(legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows))
  
  p;  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Histogram of data
do_histogram_plot = function(y_axis) {
  cat("plotting (histogram, log scale): ",x_axis," vs ",y_axis,"\n")

  # vars
  trace = paste(client_type,"histogram","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p = ggplot(data, aes_string(x=y_axis))
  p = p + geom_histogram() 
  p = p + theme_bw() + facet_grid(trace ~ .) 
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)))
  p = p + ggtitle(title) + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))

  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Summary of data in bar plot
do_summary_plot = function(y_axis) {
  cat("plotting (summary): ",x_axis," vs ",y_axis,"\n")

  # vars
  trace =  paste(client_type,"bar",y_axis,sep="_")
  title = paste("Summary of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + facet_grid(trace ~ .) + theme_bw()
  p = p + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray")
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Mean summary plot
do_mean_plot = function(y_axis) {
  cat("plotting (mean of): ",x_axis," vs ",y_axis,"\n")

  trace =  paste(client_type,"mean_bar",y_axis,sep="_")
  title = paste("Mean of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray") 
  p = p + facet_grid(trace ~ .) + theme_bw()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Max summary plot
do_max_plot = function(y_axis) {
  cat("plotting (max of): ",x_axis," vs ",y_axis,"\n")

  trace =  paste(client_type,"max_bar",y_axis,sep="_")
  title = paste("max of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="max", geom="bar", fill="white", colour="gray") 
  p = p + facet_grid(trace ~ .) + theme_bw()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Time summary plot
do_time_summary_plot = function() {
  cat("plotting Time summary\n")

  trace =  "time_summary"
  title = paste("Time Summary")
  file_name = paste(trace, output_filetype, sep=".")

  # reformat data
  cat("Reformatting data\n")
  mdata <- melt(data, id=c("mode"),measure=graphTimeStats)

  # construct plot
  cat("Constructing plot\n")
  p <- ggplot(melt(cast(mdata, mode~variable, sum)),aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity") + theme_bw()
  p = p + ggtitle(title) + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))

  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
}

### Boxplot
do_box_plot = function(y_axis) {
  cat("plotting (boxplot of): ",x_axis,", ",y_axis,"\n")

  # vars
  trace =  paste(client_type,"boxplot_bar",y_axis,sep="_")
  title = paste("Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(data, aes_string(x="factor(Bin)", y=y_axis))
  p = p + geom_boxplot()
  p = p + facet_grid(mode ~ .) + theme_bw() + ylab(paste(y_axis,"(s)")) +  xlab("Message")
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)
  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Log Boxplot
do_log_box_plot = function(y_axis) {
  cat("plotting (boxplot of): ",x_axis,", ",y_axis,"\n")

  # vars
  trace =  paste(client_type,"boxplot_log_bar",y_axis,sep="_")
  title = paste("Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(data, aes_string(x="factor(Bin)", y=y_axis)) 
  #p = p + geom_boxplot(aes(colour=factor(mode),linetype=factor(mode)))
  p = p + geom_boxplot()
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)

  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)))

  p = p + facet_grid(mode ~ .) + theme_bw() + ylab(paste(y_axis,"(s)")) +  xlab("Message")
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Boxplot
do_box_alt_plot = function(params) { 
  p_mode = params[[1]]
  y_axis = params[[2]]
  cat("plotting (boxplot of): ",p_mode," vs ",y_axis,"\n")

  mdata = subset(data, mode == p_mode)

  # vars
  trace =  paste(client_type,"boxplot_bar_alt",y_axis,p_mode,sep="_")
  title = paste("Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(mdata, aes_string(x="factor(Bin)", y=y_axis))
  p = p + geom_boxplot()
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)

  min_y = as.integer(floor(min(data[[y_axis]])))
  max_y = as.integer(ceiling(max(data[[y_axis]])))
  limits_y = c(min_y, max_y)
  breaks_y = (0:5)*diff(floor(limits_y/50)*50)/5

  #cat(y_axis," min: ", min(data[[y_axis]])," ", min_y, "\n")
  #cat(y_axis," max: ", max(data[[y_axis]])," ", max_y, "\n")
  
  p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)
  p = p + theme_bw() + ylab(paste(y_axis,"(s)")) +  xlab("Message Bin")
  p = p + theme(axis.text.x=element_text(angle=45))
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
}

### Boxplot
do_box_alt_log_plot = function(params) { 
  p_mode = params[[1]]
  y_axis = params[[2]]
  cat("plotting (log boxplot of): ",p_mode," vs ",y_axis,"\n")

  mdata = subset(data, mode == p_mode)

  # vars
  trace =  paste(client_type,"boxplot_bar_alt_log",y_axis,p_mode,sep="_")
  title = paste("Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(mdata, aes_string(x="factor(Bin)", y=y_axis))
  p = p + geom_boxplot()
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)
  
  max_y = as.integer(ceiling(max(data[[y_axis]])))
  min_y = min(data[[y_axis]])
  limits_y = c(min_y, max_y)
  
  #cat(y_axis," min: ", min(data[[y_axis]])," ", min_y, "\n")
  #cat(y_axis," max: ", max(data[[y_axis]])," ", max_y, "\n")
  
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)),
                        limits = limits_y)
  p = p + theme_bw() + ylab(paste(y_axis,"(s)")) +  xlab("Message Bin")
  p = p + theme(axis.text.x=element_text(angle=45))
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
}


print_Message = function(mdata,Message) {
  rdata = mdata[match.fun("==")(mdata[["Message"]], Message), ]
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
client_type = strsplit(client_type,"-")[[1]][1]
num_threads=1

if (client_type == "tetrinet") {
  #selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg+hint-65536-64-8", "self",
  #                   "self-t", "hint-65536-64-t", "msg+hint-65536-64-8-t")
  selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg+hint-65536-64-8", "self")
  #selected_modes = c("msg-65536-64-16", "hint-65536-64", "msg+hint-65536-64-16", "self")
  selected_modes_alt_names = c("Default", "Hint", "Default+Hint", "Self")
  #selected_modes_alt_names = c("Default", "Hint", "Default+Hint", "Self",
  #                            "Self-T","Hint-T","Default+Hint-T")
  num_threads=4
  binwidth=10
} else if (client_type == "xpilot") {
  #selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg+hint-65536-64-8", "self")
  #selected_modes_alt_names = c("Default", "Hint", "Default+Hint", "Self")
  selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg+hint-65536-64-8",
                     "msg-256-64-8", "hint-256-64", "msg+hint-256-64-8")
  selected_modes_alt_names = c("Default", "Hint", "Default+Hint",
                               "Default-Coarse", "Hint-Coarse", "Default+Hint-Coarse")
  #num_threads=2
  binwidth=100
}
cat("Client Type: ",client_type,"\n")
num_threads=1

# Read the timestamp data
read_timestamps()

# Read cliver logs
read_all_data()

# Convert list of data matrices to a single data frame
data = as.data.frame(do.call(rbind, all_data))
rm(all_data)
colnames(data) = data_frame_col_names

# Retrace integer factors to string names
for (i in seq(length(modes))) {
  data$mode[data$mode == i] <- get_mode_str(i)
}

# Remove Message times from list of time stats to graph
graphTimeStats = timeStats[c(-1,-2,-3,-4)]

# Compute OtherTime (total minus all other time stats)
otherTime = data$TimeReal + data$TimeSys
for (t in graphTimeStats) {
  otherTime = otherTime - data[t]
}
data$OtherTime = otherTime

# Compute additional stats and sub stat times
data$ExtraInstructions = data$Instructions - data$ValidPathInstructions
data$SendInstructions = data$Instructions - data$RecvInstructions
data$Time = data$TimeReal - data$EdDistHintTime - data$EdDistStatTime
data$SolverTime = data$SolverTime - data$STPTime - data$CEXTime
data$EdDistBuildTime = data$EdDistBuildTime - data$EdDistHintTime
data$EdDistTime = data$EdDistTime - data$EdDistStatTime

# Add other time list of time variables
timeStats = c(timeStats, "OtherTime")
graphTimeStats = c(graphTimeStats,"OtherTime")

# Scale time stats from microsecnds to seconds
for (tstat in c(timeStats,"Delay")) {
  data[tstat] = data[tstat] / 1000000.0
}

# Trim data by start and min Messages 
data = subset(data, Message > start_Message & Message <= as.integer(floor(min_size/binwidth))*binwidth)

# Remove erronous traces
data = subset(data, trace != 19 )

# Remove empty stats from plot list
new_plotnames = NULL
for (p in plotnames) {
  if (max(data[[p]]) != 0 | min(data[[p]]) != 0) {
    new_plotnames = c(new_plotnames, p)
  }
}
plotnames = new_plotnames

# Compute number of rows needed for legends
legend_rows = ceiling(length(unique(factor(data$mode)))/3)

###############################################################################

x_axis = "Message"

# Create individual plots for selected modes
if (length(selected_modes) != 0) {
 mode_params = selected_modes_alt_names
 y_params = c("Time","Delay")
 params = list()
 for (m in seq(length(mode_params))) {
  for (y in seq(length(y_params))) {
   params[[length(params)+1]] = c(mode_params[[m]], y_params[[y]])
  }
 }
 plotheight = default_plotheight/2
 results = mclapply(params, do_box_alt_log_plot, mc.cores=num_threads)
 results = mclapply(params, do_box_alt_plot, mc.cores=num_threads)
}

plotwidth = default_plotwidth
plotheight = default_plotheight*2
#results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_log_box_plot, mc.cores=num_threads)

plotheight = default_plotheight
do_time_summary_plot()

plotheight = length(unique(data$trace))*heightscalefactor
#results = mclapply(plotnames, do_line_alt_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_logscale_line_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_point_plot, mc.cores=num_threads)

plotheight = default_plotheight*2
#results = mclapply(c("Delay"), do_max_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_histogram_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_summary_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_mean_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)

###############################################################################
