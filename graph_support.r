#!/usr/bin/Rscript

###############################################################################
# Required Libraries
###############################################################################

library(ggplot2)
library(plyr)
library(reshape)
library(scales)
library(quantreg)
library(parallel)
library(pastecs)
library(xtable)

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
  "SymbolicVariableCount", "PassCount",
  "QueryCount","InvalidQueryCount","ValidQueryCount",
  "QueryCacheHits","QueryCacheMisses","QueryConstructCount"
)

data_frame_col_names = c(colnames, "trace", "mode", "Direction", "Bin", "Delay")

timeStats = c(
  "TimeFull","TimeReal","TimeSys","Time",
  "SolverTime","SearcherTime","STPTime","CEXTime","QueryConstructTime","ResolveTime",
  "ExecTreeTime","EdDistTime","EdDistBuildTime",
  "EdDistHintTime", "EdDistStatTime","MergeTime","RebuildTime"
)

#timestamp_colnames = c("MSGINFO","Timestamp","Direction","Bytes","SubBytes")
timestamp_colnames = c("Index","Direction","Bytes","Timestamp")

# Default parameters
min_size=.Machine$integer.max
start_Message = 1
binwidth=100
binwidth_time=5
time_scale=1000000

default_plotwidth=5
default_plotheight=5
# Presentations (larger font)
default_plotwidth=4
default_plotheight=4

heightscalefactor = 0.5
plotwidth = default_plotwidth
plotheight = default_plotheight
x_axis = "RoundNumber"
num_threads=1
#output_filetype="eps"
#output_filetype="png"
output_filetype="pdf"
timestamp_pattern = "*_client_socket.log"
data_dir="data"
use_title=FALSE

### Global Vars
timestamps <- NULL
all_data <- list()
modes <- list()
selected_modes = list()
data <- NULL

###############################################################################
### Helper Functions
###############################################################################

printf <- function(...) invisible(cat(sprintf(...),"\n"))
#debug_printf <- function(...) invisible(print(sprintf(...)))
#debug_printf <- function(...) invisible(printf(...))
debug_printf <- function(...) {}

###############################################################################
### Function: Read Timestamp data
###############################################################################

#read_timestamps = function() {
#  trace_count = 0
#  trace_total_time = 0
#  timestamp_dir = paste(root_dir,"socketlogs",sep="/")
#  debug_printf("read_timestamps: directory: %s", timestamp_dir)
#  for (file in list.files(path=timestamp_dir,pattern=timestamp_pattern)) {
#    # Read id number of timestamp file, format is str_#_...._client_socket.log
#    
#    debug_printf("read_timestamps: file: %s", file)
#    if (client_type == "openssl") {
#      # gmail_spdy_stream00_client_socket.log
#      trace = as.integer(substring(unlist(unlist(strsplit(file,"_"))[3]),7))
#    } else {
#      trace = as.integer(unlist(unlist(strsplit(file,"_"))[2]))
#    }
#    debug_printf("read_timestamps: trace: %d", trace)
#    
#    tmp_timestamps = try(read.table(paste(timestamp_dir,file,sep="/"), col.names=timestamp_colnames), silent=TRUE)
#    #cat("Reading ",file,", trace: ",trace, "\n")
#
#    # Extract just socket events, ktest objects with names: c2s and s2c
#    tmp_timestamps = subset(tmp_timestamps, Direction == "c2s" | Direction == "s2c")
#
#    if (class(tmp_timestamps) == "try-error") {
#      cat("try-error reading timestamp file\n")
#    } else {
#      trace_total_time = trace_total_time + (tmp_timestamps$Timestamp[length(tmp_timestamps[,1])] - tmp_timestamps$Timestamp[1])
#      trace_count = trace_count + 1
#      
#      cat("Reading ",file,", trace: ",trace, ", time(s): ",trace_total_time,"\n")
#      #debug_printf("Reading %s, trace: %d, time(s): %f",file,trace,trace_total_time)
#      
#      # Remove first row
#      #tmp_timestamps = tmp_timestamps[c(-1),]
#      
#      len = length(tmp_timestamps[,1]) # length of rows, not cols
#      debug_printf("%s : length: %d", file, len)
#      tmp_timestamps$trace=rep(trace, len)
#      tmp_timestamps$Message = seq(0,len-1)
#      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp - rep(tmp_timestamps$Timestamp[1],len)
#      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp * 1000000
#
#      # Add timestamps to global var
#      timestamps <<- rbind(timestamps, tmp_timestamps)
#    }
#  }
#  cat("Avg Trace Length: ",(trace_total_time/trace_count)/60,"(min)\n")
#  total_c2s_bytes = sum(subset(timestamps,Direction == "c2s")[["Bytes"]])
#  total_c2s_count = length(subset(timestamps,Direction == "c2s")[,1]) + 1
#  total_s2c_bytes = sum(subset(timestamps,Direction == "s2c")[["Bytes"]])
#  total_s2c_count = length(subset(timestamps,Direction == "s2c")[,1])
#  message_delay = trace_total_time/(total_c2s_count + total_s2c_count)
#  message_rate = (total_c2s_count + total_s2c_count)/trace_total_time
#  cat("Avg. Intermessage Delay: ",message_delay,"\n")
#  cat("Message Rate: ",message_rate,"\n")
#  cat("8 bit BW increase: ",(total_c2s_count*8)/(total_c2s_bytes*8),"\n")
#  cat("9 bit BW increase: ",(total_c2s_count*9)/(total_c2s_bytes*8),"\n")
#  cat("11 bit BW increase: ",(total_c2s_count*9)/(total_c2s_bytes*8),"\n")
#  cat("16 bit BW increase: ",(total_c2s_count*16)/(total_c2s_bytes*8),"\n")
#}
#
#adjusted_time = function(df, i) {
#  return(df$TimeReal[i] - df$EdDistHintTime[i] - df$EdDistStatTime[i])
#}

#compute_delays = function(m, trace_id) {
#  df = as.data.frame(m)
#  colnames(df) = data_frame_col_names
#  
#  ts = subset(timestamps, trace == trace_id)
#  
#  df_len = length(df[,1])
#  ts_len = length(ts[,1])
#  
#  len = min(df_len, ts_len)
#  
#  #cat("Computing Delays for ", trace_id," dflen=",df_len," tslen=",ts_len," len=", len,"\n")
#  
#  v = vector("numeric",len)
#  v[1] = 0
#  
#  for (j in seq(2,len)) {
#    #if (ts$Bytes[j] != df$SocketEventSize[j]) {
#    #  cat("Bytes mismatch ",ts$Bytes[j]," ",df$SocketEventSize[j],"\n")
#    #}
#    
#    if (ts$Timestamp[j] < v[j-1]) {
#      v[j] = v[j-1] + adjusted_time(df,j)
#    } else {
#      v[j] = ts$Timestamp[j] + adjusted_time(df,j)
#    }
#    
#    delta = v[j] - v[j-1]
#    if (delta > 200*1000000) {
#     cat("Large delta ",delta," at Message ", j,"\n")
#    }
#  }
#  v = v - ts$Timestamp[seq(len)]
#
#  rm(df)
#  rm(ts)
#
#  return(v)
#}

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

read_csv_subdir = function(data_mode_dir, data_date_dir, mode_id) {

  data_path = paste(data_dir, data_mode_dir, data_date_dir, sep="/")

  for (file in list.files(path=data_path)) {
    file_name = paste(data_path,file,sep="/")

    tmp_data = read.csv(file_name)

    # Remove last 2 round of data (finish cost)
    tmp_data = subset(tmp_data, RoundNumber < (max(tmp_data$RoundNumber)-2))

    # Remove first round of data (startup cost)
    tmp_data = subset(tmp_data, RoundNumber > 1)

    # length of rows, not cols
    len = length(tmp_data[,1])

    # extract file id (openssl, bssl, or games)
    if (client_type == "openssl" || client_type == "bssl") {
      # "gmail_spdy_stream08.ktest" or "bssl_gmail_spdy_stream08.ktest"
      file_parts <- unlist(strsplit(file,"_|\\."))
      id_segment <- file_parts[length(file_parts)-1]
      id = as.integer(substring(id_segment,7))
    } else {
      id = as.integer(unlist(unlist(strsplit(file,"_|\\."))[2]))
    }

    # Print info for this log
    cat(data_mode_dir,'\t',len,'\t',data_date_dir,'\t',file,'\t',id,'\n')

    # Add Name id
    tmp_data$trace = rep(id, len)

    # Add Mode id
    tmp_data$mode = rep(mode_id, len)

    # Set bin number
    g = c()
    for (j in seq(len)) { g = append(g,binwidth*(floor(j/binwidth))) }
    tmp_data$Bin = g

    if (min_size > length(tmp_data[,1])) {
      min_size <<- length(tmp_data[,1])
      #debug_printf("New min_size=%d", min_size)
    }

    # change absolute timestamps to relative
    tmp_data$SocketEventTimestamp = (tmp_data$SocketEventTimestamp - tmp_data$SocketEventTimestamp[1])

    # Fix non-monotonic SocketEventTimeStamps
    max_ts <- 0
    for (j in seq(len)) {
      ts <- tmp_data$SocketEventTimestamp[j]
      if (ts >= max_ts) {
        max_ts <- ts
      } else {
        debug_printf("Fixing Net timestamp: %s, Round: %i out of order, %f, %f", file_name, j, ts, max_ts)
        tmp_data$SocketEventTimestamp[j] <- max_ts
      }
    }

    ## compute verifier delay
    t_arr = vector("numeric",len)
    t_comp = vector("numeric",len)
    t_delay = vector("numeric",len)
    t_wait = vector("numeric",len)
    t_arr[1] = 0
    t_wait[1] = 0
    t_comp[1] = tmp_data$RoundRealTime[1]
    t_delay[1] = t_comp[1] - t_arr[1]
    for (j in seq(2, len)) {
      t_arr[j] = (tmp_data$SocketEventTimestamp[j] - tmp_data$SocketEventTimestamp[1])
      t_comp[j] = max(t_arr[j], t_comp[j-1]) + tmp_data$RoundRealTime[j]
      t_delay[j] = t_comp[j] - t_arr[j]
      t_wait[j] = max(t_arr[j] - t_comp[j-1], 0)
    }
    tmp_data$VerifierDelayTime = t_delay
    tmp_data$VerifierWaitTime = t_wait

    # Set timestamp bin number
    tmp_data$ArrivalBin = rep(0, len)
    #for (j in seq(len)) { g = append(g,binwidth*(floor(j/binwidth))) }
    for (j in seq(len)) {
      t = tmp_data$SocketEventTimestamp[j] / time_scale
      tmp_data$ArrivalBin[j] = binwidth_time * floor(t / binwidth_time)
    }

    # compute cumulative bandwidth
    tmp_data$BWs2c = rep(0, len)
    tmp_data$BWc2s = rep(0, len)
    tmp_data$BW = rep(0, len)
    for (j in seq(len)) {
      if (j == 1) prev = j
      else prev = j-1
      tmp_data$BWs2c[j] = tmp_data$BWs2c[prev]
      tmp_data$BWc2s[j] = tmp_data$BWc2s[prev]
      tmp_data$BW[j]    = tmp_data$BW[prev] + tmp_data$SocketEventSize[j]
      if (tmp_data$SocketEventType[j] == 0) {
        tmp_data$BWc2s[j] = tmp_data$BWc2s[j] + tmp_data$SocketEventSize[j]
      } else {
        tmp_data$BWs2c[j] = tmp_data$BWs2c[j] + tmp_data$SocketEventSize[j]
      }
    }

    # compute verification times to associate with socket event size
    tmp_data$VerifyTimeForSize = rep(0, len)
    for (j in seq(len)) {
      if (j == 1) prev = j
      else prev = j-1
      if (j == len) nxt = j
      else nxt = j+1
      if (tmp_data$SocketEventType[j] == 0 & tmp_data$SocketEventType[prev] == 0) {
        tmp_data$VerifyTimeForSize[j] = tmp_data$RoundRealTime[j]
      } else if (tmp_data$SocketEventType[j] == 1 & tmp_data$SocketEventType[nxt] == 1) {
        tmp_data$VerifyTimeForSize[j] = tmp_data$RoundRealTime[nxt]
      } else {
        tmp_data$VerifyTimeForSize[j] = 0
      }
    }


    # Add BackTrackCount if needed
    if (!("BackTrackCount" %in% colnames(tmp_data))) {
      tmp_data$BackTrackCount = rep(1, len)
    }

    #debug_printf("id = %d: ncols_data=%d ncols=%d nrows_data=%d nrows=%d", id, ncol(data), ncol(tmp_data),nrow(data), nrow(tmp_data))
    data <<- rbind(data, tmp_data)
  }
}

read_csv_data = function() {
  debug_printf("Reading: %s", paste(data_dir,sep="/"))
  for (data_mode_dir in dir(paste(data_dir,sep="/"), full.names=FALSE, recursive=FALSE)) {

    data_path = paste(data_dir, data_mode_dir, sep="/")

    data_date_dirs = sort(dir(data_path, full.names=FALSE, recursive=FALSE), decreasing=TRUE)

    if (length(selected_modes) == 0 | data_mode_dir %in% selected_modes) {
      for (data_date_dir in data_date_dirs[seq(1)]) {
        mode_id = get_mode_id(data_mode_dir)
        read_csv_subdir(data_mode_dir, data_date_dir, mode_id)
      }
    }
  }
}

###############################################################################
### Plot Functions 
###############################################################################

### Jittered point plot of data
do_point_plot = function(y, x="RoundNumber", ylab="", xlab="", tag="",plot_data=data, grid=FALSE) {
  debug_printf("Point Plot: %s %s %s %s", x, y, xlab, ylab)
 
  # remove zero values
  mdata = plot_data[match.fun('!=')(plot_data[[y]], 0), ]
  
  if (length(mdata[,1]) == 0)
    return

  # vars
  title = paste(x,"vs",y, sep=" ")
  trace = paste(paste(x,"vs",y,sep=""),client_type,"point",sep="_")
  if (tag != "")
    trace = paste(trace, tag, sep="_")
  file_name = paste(trace, output_filetype, sep=".")
 
  # default labels
  if (ylab == "") ylab = paste(y,"(s)")
  if (xlab == "") xlab = x

  # construct plot
  p = ggplot(mdata, aes_string(x=x, y=y))
  #p = p + geom_jitter(aes(colour=factor(mode),shape=factor(mode)),size=1)
  #p = p + geom_point(aes(colour=factor(mode),shape=factor(mode)),size=1)

  p = p + geom_point(aes(colour=factor(SocketEventType),shape=factor(SocketEventType)),size=2.0)
  if (grid) p = p + facet_grid(mode ~ .)
  p = p + scale_colour_grey(start=0.0,end=0.5)
  #p = p + geom_point(aes(shape=factor(SocketEventType)),size=2.0)

  #p = p + facet_grid(trace ~ .) + theme_bw() + ylab(paste(y,"(s)"))
  p = p + theme_bw() + ylab(ylab) + xlab(xlab)
  p = p + scale_y_continuous()
  #p = p + theme(legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows),
  #               shape = guide_legend(title=NULL, nrow = legend_rows))
  p = p + theme(legend.position="none")
  if (use_title)
    p = p + ggtitle(title)
  
  p;  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}
 
### Line plot of data
do_line_plot = function(y_axis,plot_x_axis=x_axis) {
  cat("plotting: (line), ",plot_x_axis," vs ",y_axis,"\n")
 
  # remove zero values
  #mdata = data[match.fun('!=')(data[[y_axis]], 0), ]
  #if (length(mdata[,1]) == 0)
  #  return
  
  # vars
  trace = paste(paste(plot_x_axis,"vs",y_axis,sep=""),client_type,"line",sep="_")
  title = paste(plot_x_axis,"vs",y_axis, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # construct plot
  #p = ggplot(mdata, aes_string(x=plot_x_axis, y=y_axis))
  p = ggplot(data, aes_string(x=plot_x_axis, y=y_axis))
  #p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5)
  p = p + geom_line(aes(colour=factor(mode)),size=0.5)
  p = p + facet_grid(trace ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_continuous()
  #p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows))
  p = p + theme(legend.position="bottom")
  if (use_title)
    p = p + ggtitle(title)
                    
  p;  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Alt. Line plot of data
do_line_alt_plot = function(y_axis,plot_x_axis=x_axis) {
  cat("plotting: (alt line), ",plot_x_axis," vs ",y_axis,"\n")
 
  # vars
  trace = paste(paste(plot_x_axis,"vs",y_axis,sep=""),client_type,"line","alt",sep="_")
  title = paste(plot_x_axis,"vs",y_axis, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # construct plot
  #p = ggplot(data, aes_string(x=plot_x_axis, y=y_axis))
  p = ggplot(data, aes_string(x=plot_x_axis, y=y_axis))
  #p = p + geom_jitter(size=1)
  p = p + geom_point(size=1)
  p = p + facet_grid(mode ~ .) + theme_bw() + ylab(paste(y_axis," Time (s)"))
  p = p + scale_y_continuous()
  #p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  if (use_title)
    p = p + ggtitle(title)

  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Alt. Line plot of data
do_line_group_plot = function(y, x=x_axis, ylab="",
                              xlab="",tag="",plot_data=data,min_y=0,max_y=0,grid=FALSE,with_points=FALSE,group_relabels=c()) {
  debug_printf("Group Line Plot: %s %s %s %s %s", x, y, xlab, ylab, tag)

  # vars

  if (tag != "")
    group_name = paste("group",tag,sep="_")
  else
    group_name = "group"

  trace = paste(paste(x,"vs",y,sep=""),client_type,"line",group_name,sep="_")
  trace = paste(paste(x,"vs",y,sep=""),client_type,"line",group_name,sep="_")
  title = paste(x,"vs",y, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # default labels
  if (ylab == "") ylab = paste(y,"(s)")
  if (xlab == "") xlab = x

  plot_data$group = interaction(plot_data$mode, plot_data$trace)
  tmp_data = plot_data

  if (length(group_relabels) != 0) {
    revalue(tmp_data$group, group_relabels) -> tmp_data$group
  }

  # construct plot
  p = ggplot(tmp_data, aes_string(x=x, y=y))
  #p = p + geom_line(aes(linetype=factor(group)),size=1.00, alpha=1/2)
  if (length(group_relabels) != 0) {
    levels_reorder <- c("Workers=1, No Padding","Workers=1, Padding","Workers=16, Padding")
    #p = p + geom_line(aes(linetype=factor(group, levels=levels_reorder))
    p = p + geom_line(aes(linetype=factor(group, levels=c("Workers=1, No Padding","Workers=1, Padding","Workers=16, Padding"))))
  } else {
    p = p + geom_line(aes(linetype=factor(group)),size=0.6)
  }
  #if (length(group_labels) == 0)
  #  p = p + geom_line(aes(linetype=factor(group)),size=1.00, alpha=1/2)
  #else
  #  p = p + geom_line(aes(linetype=factor(group,levels=group_labels)),size=1.00, alpha=1/2)
  #if (with_points) p = p + geom_point(aes(colour=factor(group),shape=factor(group)), alpha=1/2)
  if (with_points) p = p + geom_point(aes(shape=factor(group)), alpha=1/2)
  #p = p + geom_point(aes(colour=factor(group)), shape=19, alpha=1/4) + geom_smooth(aes(colour=factor(group)),level=0.99,se=FALSE)
  if (grid) p = p + facet_grid(mode ~ .)
  p = p + theme_bw() + ylab(ylab) + xlab(xlab)
  #p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  if (min_y != max_y) {
    # yscale based on all data
    #min_y = as.integer(floor(min(data[[y]])))
    #max_y = as.integer(ceiling(max(data[[y]])))

    # yscale based on all subset data
    #min_y = as.integer(floor(min(mdata[[y]])))
    #max_y = as.integer(ceiling(max(mdata[[y]])))

    limits_y = c(min_y, max_y)

    breaks_y = (0:5)*diff(floor(limits_y/5)*5)/5
    #breaks_y = (0:5)*diff(floor(limits_y))/5

    #cat(y," min: ", min(data[[y]])," ", min_y, "\n")
    #cat(y," max: ", max(data[[y]])," ", max_y, "\n")

    p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)
  } else {
    p = p + scale_y_continuous()
  }

  if (length(group_relabels) != 0) {
    p = p + scale_linetype_manual(values=c("dotted","solid","dashed","longdash"))
    p = p + theme(legend.position=c(0.70,0.45),
                  legend.background = element_rect(fill=alpha('white', 0.001)),
                  legend.text=element_text(size=7),
                  legend.title=element_blank())
  } else {
    p = p + theme(legend.position="none")
  }


  if (use_title)
    p = p + ggtitle(title)
                    
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Logscale line plot of data
do_logscale_line_plot = function(y_axis) {
  cat("plotting (line, log scale): ",x_axis," vs ",y_axis,"\n")
 
  # vars
  trace = paste( paste(x_axis,"vs",y_axis,sep=""),client_type,"line","yscalelog10",sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # construct plot
  p = ggplot(data, aes_string(x=x_axis, y=y_axis))
  #p = p + geom_line(aes(colour=factor(mode),linetype=factor(mode)),size=0.5) 
  p = p + geom_line(aes(colour=factor(mode)),size=0.5)
  p = p + facet_grid(trace ~ .) + theme_bw() + ylab(paste(y_axis,"(s)"))
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)))
  p = p + theme(legend.position="bottom")
  #p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows))
  if (use_title)
    p = p + ggtitle(title)
  
  p;  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Histogram of data
do_histogram_plot = function(y_axis) {
  cat("plotting (histogram, log scale): ",x_axis," vs ",y_axis,"\n")

  # vars
  #trace = paste(client_type,"histogram","yscalelog10", paste(x_axis,"vs",y_axis,sep=""),sep="_")
  trace = paste(paste(x_axis,"vs",y_axis,sep=""),client_type,"histogram","yscalelog10",sep="_")
  title = paste(x_axis,"vs",y_axis,"with","log10","yscale", sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p = ggplot(data, aes_string(x=y_axis))
  p = p + geom_histogram() 
  p = p + theme_bw() + facet_grid(trace ~ .) 
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)))
  p = p + theme(legend.position="bottom")
  p = p + guides(colour = guide_legend(title=NULL, nrow = legend_rows), linetype = guide_legend(title=NULL, nrow = legend_rows))
  if (use_title)
    p = p + ggtitle(title)

  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Summary of data in bar plot
do_summary_plot = function(y_axis) {
  cat("plotting (summary): ",x_axis," vs ",y_axis,"\n")

  # vars
  #trace =  paste(client_type,"bar",y_axis,sep="_")
  trace =  paste(y_axis,client_type,"bar",sep="_")
  title = paste("Summary of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + facet_grid(trace ~ .) + theme_bw()
  p = p + stat_summary(fun.y="sum", geom="bar", fill="white", colour="gray")
  p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  if (use_title)
    p = p + ggtitle(title)
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Mean summary plot
do_mean_plot = function(y_axis) {
  cat("plotting (mean of): ",x_axis," vs ",y_axis,"\n")

  #trace =  paste(client_type,"mean_bar",y_axis,sep="_")
  trace =  paste(y_axis,client_type,"mean_bar",sep="_")
  title = paste("Mean of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="mean", geom="bar", fill="white", colour="gray") 
  p = p + facet_grid(trace ~ .) + theme_bw()
  p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  if (use_title)
    p = p + ggtitle(title)
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Max summary plot
do_max_plot = function(y_axis) {
  cat("plotting (max of): ",x_axis," vs ",y_axis,"\n")

  #trace =  paste(client_type,"max_bar",y_axis,sep="_")
  trace =  paste(y_axis,client_type,"max_bar",sep="_")
  title = paste("max of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  p <- ggplot(data, aes_string(x="mode", y=y_axis)) 
  p = p + stat_summary(fun.y="max", geom="bar", fill="white", colour="gray") 
  p = p + facet_grid(trace ~ .) + theme_bw()
  p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  if (use_title)
    p = p + ggtitle(title)
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Time summary plot
do_time_summary_plot = function() {
  cat("plotting (time_summary)\n")
  trace =  paste(client_type,"time_summary",sep="_")
  title = paste("Time Summary")
  file_name = paste(trace, output_filetype, sep=".")
  
  # reformat data
  mdata <- melt(data, id=c("mode"),measure=graphTimeStats)
  cdata <- cast(mdata, mode~variable, sum, margins="grand_col")
  
  #for (statstr in graphTimeStats) {
  #  cdata[[statstr]] = cdata[[statstr]] / cdata[["(all)"]]
  #}
  mcdata = melt(cdata);
  mcdata = subset(mcdata, variable != "(all)")

  # construct plot
  #p <- ggplot(melt(cdata),aes(x=mode,y=value,fill=factor(variable)))
  p <- ggplot(mcdata,aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity", width=.5)

  #p = p + scale_fill_grey(labels=graphTimeLabels,start = 0.2, end = 0.8)
  p = p + scale_fill_hue(labels=graphTimeLabels)

  p = p + theme_bw()

  #p = p + scale_y_continuous(breaks=c(0.0,0.5,1.0), labels=c("0%","50%","100%"))
  p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p = p + theme(axis.title.x=element_blank())
  p = p + ylab("Time")
  p = p + guides(fill = guide_legend(title=NULL,reverse=TRUE))

  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
  rm(cdata)
}

### Instruction summary plot
do_instruction_summary_plot = function() {
  cat("plotting (inst_summary)\n")
  trace =  paste(client_type,"instruction_summary",sep="_")
  title = paste("Instruction Summary")
  file_name = paste(trace, output_filetype, sep=".")

  # reformat data
  mdata <- melt(data, id=c("mode"),measure=graphInstructionStats)
  cdata <- cast(mdata, mode~variable, sum, margins="grand_col")
  print(cdata);

  #for (statstr in graphInstructionStats) {
  #  cdata[[statstr]] = cdata[[statstr]] / cdata[["(all)"]]
  #}
  mcdata = melt(cdata);
  mcdata = subset(mcdata, variable != "(all)")
  
  # construct plot
  #p <- ggplot(melt(cdata),aes(x=mode,y=value,fill=factor(variable)))
  p <- ggplot(mcdata,aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity", width=.5)
  
  #p = p + scale_fill_grey(labels=graphTimeLabels,start = 0.2, end = 0.8)
  p = p + scale_fill_hue(labels=graphInstructionLabels)
  
  p = p + theme_bw()
  
  #p = p + scale_y_continuous(breaks=c(0.0,0.5,1.0), labels=c("0%","50%","100%"))
  p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p = p + theme(axis.title.x=element_blank())
  p = p + ylab("Instruction Count")
  p = p + guides(fill = guide_legend(title=NULL,reverse=TRUE))
  
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
  rm(cdata)
}


### Boxplot
do_box_plot = function(y,x="Bin",ylab="",xlab="",tag="",plot_data=data,grid=TRUE,limits_y=c()) {
  debug_printf("Box Plot: %s %s %s", x, y, tag)

  # vars
  trace =  paste(y,client_type,"boxplot_bar",tag,sep="_")
  title = paste("Boxplot of",y,"over",min_size,"Messages",tag,sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # default labels
  if (ylab == "") ylab = paste(y,"(s)")
  if (xlab == "") xlab = "Message"

  # This is only needed if we have an empty Bin
  # We set the factor levels to be equal to the levels for the entire
  # data set for x
  aes_x_str = paste("factor(",x,",levels=levels(factor(data$",x,")))",sep="")

  # construct plot
  p <- ggplot(plot_data, aes_string(x=aes_x_str, y=y))
  p = p + geom_boxplot()
  if (grid) p = p + facet_grid(mode ~ .)
  p = p + theme_bw() + ylab(ylab) + xlab(xlab)
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)

  if (length(limits_y) != 2) {
    ## yscale based on scale_data
    min_y = as.integer(floor(min(data[[y]])))
    max_y = as.integer(ceiling(max(data[[y]])))

    # yscale based on plot_data
    #min_y = as.integer(floor(min(plot_data[[y]])))
    #max_y = as.integer(ceiling(max(plot_data[[y]])))
    limits_y = c(min_y, max_y)
  }

  if (limits_y[2] > 5)
    breaks_y = (0:5)*diff(floor(limits_y/5)*5)/5
  else
    breaks_y = (0:5)*diff(floor(limits_y))/5

  #cat(y," min: ", min(data[[y]])," ", min_y, "\n")
  #cat(y," max: ", max(data[[y]])," ", max_y, "\n")

  p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)
  p = p + scale_x_discrete(drop=FALSE) # plot all levels, even if empty

  p = p + theme(axis.text.x=element_text(angle=45))

  if (use_title)
    p = p + ggtitle(title)
  
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}

### Cross-client (XC) Boxplot
do_box_plot_xc = function(y, x="Bin", ylab="", xlab="", tag="",
                       plot_data=NULL, full_data=NULL,
                       grid=TRUE,limits_y=c(),remove_legend=FALSE) {
  debug_printf("Box Plot: %s %s %s", x, y, tag)

  # client types
  client_types <- paste(unique(plot_data$Client), collapse = "_")

  # vars
  if (remove_legend) {
    trace = paste(y,"boxplot_bar",client_types,tag,"nolegend",sep="_")
  } else {
    trace = paste(y,"boxplot_bar",client_types,tag,sep="_")
  }
  title = paste("Boxplot of",y,"over",min_size,"Messages",tag,sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # default labels
  if (ylab == "") ylab = paste(y,"(s)")
  if (xlab == "") xlab = "Message"

  # This is only needed if we have an empty Bin
  # We set the factor levels to be equal to the levels for the entire
  # data set for x
  aes_x_str = paste("factor(",x,",levels=levels(factor(full_data$",x,")))",
                    sep="")

  # construct plot
  p <- ggplot(plot_data, aes_string(x=aes_x_str, y=y, fill="Client"))
  p <- p + geom_boxplot(position=position_dodge(width=0.8))
  if (grid) p <- p + facet_grid(mode ~ .)
  p <- p + theme_bw(base_size = 16) + ylab(ylab) + xlab(xlab)
  p <- p + scale_fill_grey(start = 0.4, end = 0.9)
  p <- p + stat_summary(fun.y=mean, geom="point", shape=5, size=3, position=position_dodge(width=0.8))
  if (remove_legend) {
    p <- p + guides(fill=FALSE)
  } else {
    p <- p + theme(legend.position = c(1,1), legend.justification = c(1,1))
  }

  if (length(limits_y) != 2) {
    ## yscale based on full_data
    min_y = as.integer(floor(min(full_data[[y]])))
    max_y = as.integer(ceiling(max(full_data[[y]])))

    # yscale based on plot_data
    #min_y = as.integer(floor(min(plot_data[[y]])))
    #max_y = as.integer(ceiling(max(plot_data[[y]])))
    limits_y = c(min_y, max_y)
  }

  if (limits_y[2] > 5)
    breaks_y = (0:5)*diff(floor(limits_y/5)*5)/5
  else
    breaks_y = (0:5)*diff(floor(limits_y))/5

  #cat(y," min: ", min(full_data[[y]])," ", min_y, "\n")
  #cat(y," max: ", max(full_data[[y]])," ", max_y, "\n")

  p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)
  p = p + scale_x_discrete(drop=FALSE) # plot all levels, even if empty

  p = p + theme(axis.text.x=element_text(angle=45))

  if (use_title)
    p = p + ggtitle(title)

  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
}


### Log Boxplot
do_log_box_plot = function(y_axis) {
  cat("plotting (boxplot of): ",x_axis,", ",y_axis,"\n")

  # vars
  #trace =  paste(client_type,"boxplot_log_bar",y_axis,sep="_")
  trace =  paste(y_axis,client_type,"boxplot_log_bar",sep="_")
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
  debug_printf("Box Plot: %s %s", p_mode, y_axis)

  mdata = subset(data, mode == p_mode)
  #mdata = mdata[match.fun('>')(mdata[[y_axis]], 0.5), ]

  # vars
  #trace =  paste(client_type,"boxplot_bar_alt",y_axis,p_mode,sep="_")
  #trace =  paste(y_axis,p_mode,client_type,"boxplot_bar_alt",sep="_")
  trace =  paste(client_type,p_mode,y_axis,"boxplot_bar_alt",sep="_")
  title = paste("Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  title = paste(p_mode,": Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(mdata, aes_string(x="factor(Bin)", y=y_axis))
  p = p + geom_boxplot(outlier.size=1)
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)

  # yscale based on all data
  #min_y = as.integer(floor(min(data[[y_axis]])))
  #max_y = as.integer(ceiling(max(data[[y_axis]])))

  # yscale based on all subset data
  min_y = as.integer(floor(min(mdata[[y_axis]])))
  max_y = as.integer(ceiling(max(mdata[[y_axis]])))

  limits_y = c(min_y, max_y)

  #breaks_y = (0:5)*diff(floor(limits_y/50)*50)/5
  breaks_y = (0:5)*diff(floor(limits_y))/5

  #cat(y_axis," min: ", min(data[[y_axis]])," ", min_y, "\n")
  #cat(y_axis," max: ", max(data[[y_axis]])," ", max_y, "\n")
  
  p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)
  p = p + theme_bw() + ylab(paste(y_axis,"(s)")) +  xlab("Message Bin")
  p = p + theme(axis.text.x=element_text(angle=45))
  if (use_title)
    p = p + ggtitle(title)
  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
}

### Boxplot
do_box_alt_log_plot = function(params) { 
  p_mode = params[[1]]
  y_axis = params[[2]]
  debug_printf("Group Line Plot: %s %s", p_mode, y_axis)

  mdata = subset(data, mode == p_mode)

  # vars
  #trace =  paste(client_type,"boxplot_bar_alt_log",y_axis,p_mode,sep="_")
  trace =  paste(client_type,p_mode,y_axis,"boxplot_bar_alt_log",sep="_")
  title = paste(p_mode,": Log Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(mdata, aes_string(x="factor(Bin)", y=y_axis))
  p = p + geom_boxplot()
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)
  
  # yscale based on all data
  max_y = as.integer(ceiling(max(data[[y_axis]])))
  min_y = min(data[[y_axis]])

  # yscale based on all subset data
  max_y = as.integer(ceiling(max(mdata[[y_axis]])))
  min_y = min(mdata[[y_axis]])

  limits_y = c(min_y, max_y)
  
  #cat(y_axis," min: ", min(data[[y_axis]])," ", min_y, "\n")
  #cat(y_axis," max: ", max(data[[y_axis]])," ", max_y, "\n")

  # causes error
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
                        labels = trans_format("log10", math_format(10^.x)),
                        limits = limits_y)
  #p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
  #                      labels = trans_format("log10", math_format(10^.x)))
  
  #p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x))

  p = p + theme_bw() + ylab(paste(y_axis,"(s)")) +  xlab("Message Bin")
  p = p + theme(axis.text.x=element_text(angle=45))
  if (use_title)
    p = p + ggtitle(title)
  p;

  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)
  rm(mdata)
}

## Boxplot
do_last_message_box_plot = function(y_axis) { 
  #p_mode = params[[1]]
  #y_axis = params[[2]]
  cat("plotting (last message boxplot of): ",x_axis," vs ",y_axis,"\n")
  
  ldata = data
  #last_round_data = list() 
  for (m in unique(factor(data$mode))) {
    for (t in unique(factor(data$trace))) {
      tmp_data = subset(data, mode == m & trace == t)
      last_message = max(tmp_data$Message)
      #cat("Last message: ",last_message," in mode: ",m," and trace ",t,"\n")
      #last_round_data[length(last_round_data)] = subset(tmp_data, Message == last_message)
      ldata = subset(ldata, (mode != m) | (mode == m & trace != t) | (mode == m & trace == t & Message == last_message))
    }
    tmp_data = subset(ldata, mode == m)
    cat(m,"- mean: ",mean(tmp_data[[y_axis]]),"\n")
    
    cat(m,"- median: ",median(tmp_data[[y_axis]]),"\n")
    
    cat(m,"- max: ",max(tmp_data[[y_axis]]),"\n")
    
    cat(m,"- min: ",min(tmp_data[[y_axis]]),"\n")
    
  }
  cat("Length: ", length(ldata[,1]),"\n")
  cat(unique(factor(ldata$mode)),"\n")
  cat(unique(factor(ldata$trace)),"\n")
  #mdata = as.data.frame(do.call(rbind, last_round_data))
  
  # vars
  trace =  paste(client_type,"boxplot_bar_last_round",y_axis,sep="_")
  title = paste("Boxplot of last round",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
  
  # construct plot
  p <- ggplot(ldata, aes_string(x="mode", y=y_axis))
  p = p + geom_boxplot()
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)
  
  #min_y = as.integer(floor(min(data[[y_axis]])))
  #max_y = as.integer(ceiling(max(data[[y_axis]])))
  #limits_y = c(min_y, max_y)
  #breaks_y = (0:5)*diff(floor(limits_y/50)*50)/5
  
  #cat(y_axis," min: ", min(data[[y_axis]])," ", min_y, "\n")
  #cat(y_axis," max: ", max(data[[y_axis]])," ", max_y, "\n")
  #p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)
  p = p + scale_y_continuous()
  #p = p + facet_grid(mode ~ .)
  p = p + theme_bw()
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

parse_client_type = function() {
  client_type = rev(strsplit(root_dir,"/")[[1]])[1]
  client_type = strsplit(client_type,"-")[[1]][1]
  return(client_type)
}

formal_client_type <- function(raw_client_name) {
    client_prefix <- unlist(strsplit(raw_client_name, "-"))[1]
    if (client_prefix == "openssl") {
        return("OpenSSL")
    } else if (client_prefix == "bssl") {
        return("BoringSSL")
    } else {
        return(client_prefix)
    }
}

read_processed_data <- function(datadir) {
    alldata <- data.frame()
    processed_data_files <- dir(datadir)
    for (f in processed_data_files) {

        # Extract client type, data_tag, and bin_width from filename
        f_sans_ext <- strsplit(f, "\\.")[[1]] # remove "*.csv" extension
        f_parts <- unlist(strsplit(f_sans_ext, "__")) # double underscore
        client <- f_parts[1]
        data_tag <- f_parts[2]
        bin_width <- f_parts[3]

        # Read data and add Client, DataTag, and ArrivalBinWidth columns
        df <- read.csv(paste(datadir, f, sep="/"), header = TRUE)
        df$Client <- formal_client_type(client)
        df$DataTag <- data_tag
        df$ArrivalBinWidth <- bin_width

        alldata <- rbind(alldata, df)
    }

    # Sort client levels so that OpenSSL comes before BoringSSL
    client_levels <- unique(sort(alldata$Client, decreasing=TRUE))
    alldata$Client <- factor(alldata$Client, levels=client_levels)
    alldata$DataTag <- factor(alldata$DataTag)

    return(alldata)
}

###############################################################################

