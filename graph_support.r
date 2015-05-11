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
start_Message = 2
binwidth=20
binwidth_time=30
time_scale=1000000
default_plotwidth=6
default_plotheight=6
heightscalefactor = 0.75
heightscalefactor = 0.5
plotwidth = default_plotwidth
plotheight = default_plotheight
x_axis = "RoundNumber"
num_threads=1
#output_filetype="eps"
output_filetype="png"
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

printf <- function(...) invisible(print(sprintf(...)))
debug_printf <- function(...) invisible(print(sprintf(...)))
#debug_printf <- function(...) {}

###############################################################################
### Function: Read Timestamp data
###############################################################################

read_timestamps = function() {
  trace_count = 0
  trace_total_time = 0
  timestamp_dir = paste(root_dir,"socketlogs",sep="/")
  debug_printf("read_timestamps: directory: %s", timestamp_dir)
  for (file in list.files(path=timestamp_dir,pattern=timestamp_pattern)) {
    # Read id number of timestamp file, format is str_#_...._client_socket.log
    
    debug_printf("read_timestamps: file: %s", file)
    if (client_type == "openssl") {
      # gmail_spdy_stream00_client_socket.log
      trace = as.integer(substring(unlist(unlist(strsplit(file,"_"))[3]),7))
    } else {
      trace = as.integer(unlist(unlist(strsplit(file,"_"))[2]))
    }
    debug_printf("read_timestamps: trace: %d", trace)
    
    tmp_timestamps = try(read.table(paste(timestamp_dir,file,sep="/"), col.names=timestamp_colnames), silent=TRUE)
    #cat("Reading ",file,", trace: ",trace, "\n")

    # Extract just socket events, ktest objects with names: c2s and s2c
    tmp_timestamps = subset(tmp_timestamps, Direction == "c2s" | Direction == "s2c")

    if (class(tmp_timestamps) == "try-error") {
      cat("try-error reading timestamp file\n")
    } else {
      trace_total_time = trace_total_time + (tmp_timestamps$Timestamp[length(tmp_timestamps[,1])] - tmp_timestamps$Timestamp[1])
      trace_count = trace_count + 1
      
      cat("Reading ",file,", trace: ",trace, ", time(s): ",trace_total_time,"\n")
      #debug_printf("Reading %s, trace: %d, time(s): %f",file,trace,trace_total_time)
      
      # Remove first row
      #tmp_timestamps = tmp_timestamps[c(-1),]
      
      len = length(tmp_timestamps[,1]) # length of rows, not cols
      debug_printf("%s : length: %d", file, len)
      tmp_timestamps$trace=rep(trace, len)
      tmp_timestamps$Message = seq(0,len-1)
      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp - rep(tmp_timestamps$Timestamp[1],len)
      tmp_timestamps$Timestamp = tmp_timestamps$Timestamp * 1000000

      # Add timestamps to global var
      timestamps <<- rbind(timestamps, tmp_timestamps)
    }
  }
  cat("Avg Trace Length: ",(trace_total_time/trace_count)/60,"(min)\n")
  total_c2s_bytes = sum(subset(timestamps,Direction == "c2s")[["Bytes"]])
  total_c2s_count = length(subset(timestamps,Direction == "c2s")[,1]) + 1
  total_s2c_bytes = sum(subset(timestamps,Direction == "s2c")[["Bytes"]])
  total_s2c_count = length(subset(timestamps,Direction == "s2c")[,1])
  message_delay = trace_total_time/(total_c2s_count + total_s2c_count)
  message_rate = (total_c2s_count + total_s2c_count)/trace_total_time
  cat("Avg. Intermessage Delay: ",message_delay,"\n")
  cat("Message Rate: ",message_rate,"\n")
  cat("8 bit BW increase: ",(total_c2s_count*8)/(total_c2s_bytes*8),"\n")
  cat("9 bit BW increase: ",(total_c2s_count*9)/(total_c2s_bytes*8),"\n")
  cat("11 bit BW increase: ",(total_c2s_count*9)/(total_c2s_bytes*8),"\n")
  cat("16 bit BW increase: ",(total_c2s_count*16)/(total_c2s_bytes*8),"\n")
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

  data_path = paste(data_dir, data_mode_dir, data_date_dir, sep="/")
  
  for (file in list.files(path=data_path)) {
    file_name = paste(data_path,file,sep="/")
    debug_printf("Reading: %s", file_name)
    
    # Read number of lines in file
    nrows = as.integer(unlist(unlist(strsplit(system(paste("wc -l ", file_name, sep=""), intern=T)," "))[1]))
    ncols = length(colnames)
    
    # Read file
    tmp_data = try(matrix(scan(file_name,what=integer(),nmax=nrows*ncols,quiet=TRUE),nrow=nrows,ncol=ncols,byrow=TRUE), silent=FALSE)
    
    if (class(tmp_data) != "try-error") {
      
      # length of rows, not cols
      len = length(tmp_data[,1]) 
      
      # extract file id
      if (client_type == "openssl") {
        id = as.integer(substring(unlist(unlist(strsplit(file,"_|\\."))[3]),7))
      } else {
        id = as.integer(unlist(unlist(strsplit(file,"_|\\."))[2]))
      }
      debug_printf("id = %d", id)
      
      cat(data_mode_dir,'\t',len,'\t',data_date_dir,'\t',file,'\t',id,'\n')
      
      # Add Name id 
      tmp_data = cbind(tmp_data, rep(id, len))
      
      # Add Mode id
      tmp_data = cbind(tmp_data, rep(mode_id, len))
              
      # Add Direction
      if (!is.null(timestamps)) {
        ts = subset(timestamps, trace == id)
        directions = as.integer(factor(ts$Direction))

        if (length(directions) < len) {
          directions = c(directions, rep(0, len - length(directions)))
        }
        tmp_data = cbind(tmp_data, directions[seq(len)])
      } else {
        cat("not using direction\n")
        tmp_data = cbind(tmp_data, rep(0, len))
      }

      # Set bin number
      g = c()
      for (j in seq(len)) { g = append(g,binwidth*(floor(j/binwidth))) }
      tmp_data = cbind(tmp_data, g)
      
      # Add placeholder for Delay
      tmp_data = cbind(tmp_data, rep(0, len))

      # Compute delay values
      if (!is.null(timestamps) && length(subset(timestamps, trace == id)[,1]) > 0) {
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
  
  for (data_mode_dir in dir(paste(data_dir,sep="/"), full.names=FALSE, recursive=FALSE)) {
    
    data_path = paste(data_dir, data_mode_dir, sep="/")
    
    data_date_dirs = sort(dir(data_path, full.names=FALSE, recursive=FALSE), decreasing=TRUE)
    
    if (length(selected_modes) == 0 | data_mode_dir %in% selected_modes) {
      for (data_date_dir in data_date_dirs[seq(1)]) {
        mode_id = get_mode_id(data_mode_dir)
        read_data_subdir(data_mode_dir, data_date_dir, mode_id)
      }
    }
  }
}

read_csv_subdir = function(data_mode_dir, data_date_dir, mode_id) {

  data_path = paste(data_dir, data_mode_dir, data_date_dir, sep="/")

  for (file in list.files(path=data_path)) {
    file_name = paste(data_path,file,sep="/")

    tmp_data = read.csv(file_name)

    # Remove last 2 round of data (finish cost)
    tmp_data = subset(tmp_data, RoundNumber < (max(tmp_data$RoundNumber)-2))

    # length of rows, not cols
    len = length(tmp_data[,1])

    # extract file id
    if (client_type == "openssl") {
      id = as.integer(substring(unlist(unlist(strsplit(file,"_|\\."))[3]),7))
    } else {
      id = as.integer(unlist(unlist(strsplit(file,"_|\\."))[2]))
    }

    debug_printf("id = %d", id)
    cat(data_mode_dir,'\t',len,'\t',data_date_dir,'\t',file,'\t',id,'\n')

    #data_frame_col_names = c(colnames, "trace", "mode", "Direction", "Bin", "Delay")

    # Add Name id
    tmp_data$trace = rep(id, len)

    # Add Mode id
    #tmp_data = cbind(tmp_data, rep(mode_id, len))
    tmp_data$mode = rep(mode_id, len)

    # Set bin number
    g = c()
    for (j in seq(len)) { g = append(g,binwidth*(floor(j/binwidth))) }
    #tmp_data = cbind(tmp_data, g)
    tmp_data$Bin = g

    if (min_size > length(tmp_data[,1])) {
      min_size <<- length(tmp_data[,1])
    }

    # change absolute timestamps to relative
    tmp_data$SocketEventTimestamp = (tmp_data$SocketEventTimestamp - tmp_data$SocketEventTimestamp[1])
    #tmp_data$SocketEventTimestamp = pmax(tmp_data$SocketEventTimestamp, rep(0, len))

    # Fix non-monotonic SocketEventTimeStamps
    max_ts <- 0
    for (j in seq(len)) {
      ts <- tmp_data$SocketEventTimestamp[j]
      if (ts >= max_ts) {
        max_ts <- ts
      } else {
        debug_printf("Fixing Net timestamp: %s, Round: %i out of order, %f, %f", file_name, j, ts, max_ts)
        tmp_data$SocketEventTimestamp[j] <- max_ts
        max_ts <- ts
      }
    }

    # compute verifier delay
    v = vector("numeric",len)
    v[1] = 0
    for (j in seq(2, len)) {
      v_delay = (v[j-1] + tmp_data$RoundRealTime[j]) - (tmp_data$SocketEventTimestamp[j] - tmp_data$SocketEventTimestamp[j-1])
      #debug_printf("Delay: %s, Round: %i Delay: %f", file_name, j, v_delay / 1000000.0)
      if (v_delay < 0) {
        #debug_printf("Delay: %s, Round: %i is ahead: %i", file_name, j, v_delay)
        v_delay = 0;
      }
      v[j] = v_delay;
    }
    tmp_data$VerifierDelayTime = v

    # compute verifier delay (minus solvertime)
    v = vector("numeric",len)
    v[1] = 0
    for (j in seq(2, len)) {
      v_delay = (v[j-1] + (tmp_data$RoundRealTime[j] - tmp_data$BindingsSolveTime[j])) - (tmp_data$SocketEventTimestamp[j] - tmp_data$SocketEventTimestamp[j-1])
      #debug_printf("SolverDelay: %s, Round: %i Delay: %f", file_name, j, v_delay / 1000000.0)
      if (v_delay < 0) {
        #debug_printf("Delay: %s, Round: %i is ahead: %i", file_name, j, v_delay)
        v_delay = 0;
      }
      v[j] = v_delay;
    }
    tmp_data$VerifierMinusSolverDelayTime = v

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
      #if (tmp_data$SocketEventType[j] == 0) {
        tmp_data$VerifyTimeForSize[j] = tmp_data$RoundRealTime[j]
      } else if (tmp_data$SocketEventType[j] == 1 & tmp_data$SocketEventType[nxt] == 1) {
      #} else if (tmp_data$SocketEventType[j] == 1) {
        tmp_data$VerifyTimeForSize[j] = tmp_data$RoundRealTime[nxt]
      } else {
        tmp_data$VerifyTimeForSize[j] = 0
      }
    }

    # add data to global data list
    #all_data[[length(all_data) + 1]] <<- tmp_data
    data <<- rbind(data, tmp_data)
  }
}

read_csv_data = function() {

  debug_printf("Reading: %s", paste(data_dir,sep="/"))
  for (data_mode_dir in dir(paste(data_dir,sep="/"), full.names=FALSE, recursive=FALSE)) {

    data_path = paste(data_dir, data_mode_dir, sep="/")

    data_date_dirs = sort(dir(data_path, full.names=FALSE, recursive=FALSE), decreasing=TRUE)
    cat(data_path, "\n")

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
do_point_plot = function(y,x=x_axis,ylab="",xlab="") {
  cat("plotting: (point), ",x," vs ",y,"\n")
 
  # remove zero values
  mdata = data[match.fun('!=')(data[[y]], 0), ]
  
  if (length(mdata[,1]) == 0)
    return
  
  # vars
  trace = paste(paste(x,"vs",y,sep=""),client_type,"point",sep="_")
  title = paste(x,"vs",y, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")
 
  # default labels
  if (ylab == "") ylab = paste(y,"(s)")
  if (xlab == "") xlab = x

  # construct plot
  p = ggplot(mdata, aes_string(x=x, y=y))
  #p = p + geom_jitter(aes(colour=factor(mode),shape=factor(mode)),size=1)
  #p = p + geom_point(aes(colour=factor(mode),shape=factor(mode)),size=1)
  p = p + geom_point(aes(colour=factor(SocketEventType),shape=factor(SocketEventType)),size=2.0)
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
do_line_group_plot = function(y, x=x_axis, ylab="", xlab="",plot_data=data,min_y=0,max_y=0) {
  #cat("plotting: (group line), ", x, " vs ", y, "\n")
  debug_printf("plotting: (group line) %s vs %s", x, y)

  # vars
  trace = paste(paste(x,"vs",y,sep=""),client_type,"line","group",sep="_")
  title = paste(x,"vs",y, sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # default labels
  if (ylab == "") ylab = paste(y,"(s)")
  if (xlab == "") xlab = x

  # construct plot
  p = ggplot(plot_data, aes_string(x=x, y=y))
  p = p + geom_line(aes(colour=factor(trace)),size=0.5)
  #p = p + facet_grid(mode ~ .) + theme_bw() + ylab(ylab) + xlab(xlab)
  p = p + theme_bw() + ylab(ylab) + xlab(xlab)
  p = p + scale_y_continuous()
  #p = p + theme(axis.title.x=element_blank(), axis.text.x=element_text(angle=-90))
  p = p + theme(legend.position="none")

  if (min_y != max_y) {
    # yscale based on all data
    #min_y = as.integer(floor(min(data[[y]])))
    #max_y = as.integer(ceiling(max(data[[y]])))

    # yscale based on all subset data
    #min_y = as.integer(floor(min(mdata[[y]])))
    #max_y = as.integer(ceiling(max(mdata[[y]])))

    limits_y = c(min_y, max_y)

    breaks_y = (0:5)*diff(floor(limits_y/50)*50)/5
    #breaks_y = (0:5)*diff(floor(limits_y))/5

    #cat(y," min: ", min(data[[y]])," ", min_y, "\n")
    #cat(y," max: ", max(data[[y]])," ", max_y, "\n")

    p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)
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
do_box_plot = function(y, x="factor(Bin)", ylab="", xlab="", tag="", plot_data=data) {
  cat("plotting (boxplot of): ",x,", ",y,"\n")

  # vars
  trace =  paste(y,client_type,"boxplot_bar",tag,sep="_")
  title = paste("Boxplot of",y,"over",min_size,"Messages",tag,sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # default labels
  if (ylab == "") ylab = paste(y,"(s)")
  if (xlab == "") xlab = "Message"

  # construct plot
  p <- ggplot(plot_data, aes_string(x=x, y=y))
  p = p + geom_boxplot()
  p = p + facet_grid(mode ~ .) + theme_bw() + ylab(ylab) + xlab(xlab)
  p = p + stat_summary(fun.y=mean, geom="point", shape=5, size=3)

  # yscale based on all data
  min_y = as.integer(floor(min(data[[y]])))
  max_y = as.integer(ceiling(max(data[[y]])))

  # yscale based on all subset data
  #min_y = as.integer(floor(min(mdata[[y]])))
  #max_y = as.integer(ceiling(max(mdata[[y]])))

  limits_y = c(min_y, max_y)

  #breaks_y = (0:5)*diff(floor(limits_y/50)*50)/5
  breaks_y = (0:5)*diff(floor(limits_y))/5

  #cat(y," min: ", min(data[[y]])," ", min_y, "\n")
  #cat(y," max: ", max(data[[y]])," ", max_y, "\n")

  p = p + scale_y_continuous(limits=limits_y,breaks=breaks_y)

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
  cat("plotting (boxplot of): ",p_mode," vs ",y_axis,"\n")

  mdata = subset(data, mode == p_mode)

  # vars
  #trace =  paste(client_type,"boxplot_bar_alt",y_axis,p_mode,sep="_")
  trace =  paste(y_axis,p_mode,client_type,"boxplot_bar_alt",sep="_")
  title = paste("Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  title = paste(p_mode,": Boxplot of",y_axis,"over",min_size,"Messages",sep=" ")
  file_name = paste(trace, output_filetype, sep=".")

  # construct plot
  p <- ggplot(mdata, aes_string(x="factor(Bin)", y=y_axis))
  p = p + geom_boxplot()
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
  cat("plotting (log boxplot of): ",p_mode," vs ",y_axis,"\n")

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
  
  max_y = as.integer(ceiling(max(data[[y_axis]])))
  min_y = min(data[[y_axis]])
  limits_y = c(min_y, max_y)
  
  #cat(y_axis," min: ", min(data[[y_axis]])," ", min_y, "\n")
  #cat(y_axis," max: ", max(data[[y_axis]])," ", max_y, "\n")

  # causes error
  #p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x),
  #                      labels = trans_format("log10", math_format(10^.x)),
  #                      limits = limits_y)
  
  p = p + scale_y_log10(breaks = trans_breaks("log10", function(x) 10^x))

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

###############################################################################

