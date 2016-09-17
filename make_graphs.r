#!/usr/bin/Rscript

args=commandArgs(trailingOnly=TRUE)

###############################################################################
# Source the initial configuration and functions
###############################################################################

source("gsec-support/graph_support.r")

###############################################################################
# Set or get the root_dir
###############################################################################

root_dir="data/results"

# Read data file location from commandline or use hardcoded value
if (length(args) > 0) {
  root_dir = args[1]
}

# data tag
tag=args[2]

## binwidth for boxplot graphs
#binwidth=as.numeric(args[3])

# time binwidth (seconds) for boxplot graphs
binwidth_time=as.numeric(args[3])

# run_prefix (e.g., "2016-09-16.15:21:12")
run_prefix <- args[4]

## modes to graph
arg_modes=args[-1:-4]

###############################################################################
# Create output dirs
###############################################################################

data_name="data"
output_name="plots"

data_dir = paste(root_dir, data_name, tag, sep="/")
save_dir = paste(root_dir, output_name, tag, run_prefix, sep="/")

dir.create(save_dir, recursive=TRUE)

###############################################################################
# Client specific configuration
###############################################################################

client_type = parse_client_type()

selected_modes = arg_modes
selected_modes_alt_names = arg_modes

num_threads=64

###############################################################################
# Read and parse the data
###############################################################################

printf("\nREADING INPUT DATA")
source("gsec-support/read_data.r")

###############################################################################
# Compute number of rows needed for legends
###############################################################################

legend_rows = ceiling(length(unique(factor(data$mode)))/3)

###############################################################################
# Create individual plots for selected modes
###############################################################################

# columns to skip
skipcolnames = c('Bin','trace','RoundNumber','Queries','Quer','SocketEvent')

# plot data that is numeric and non-zero
plotnames = c()
empty_stats = c()
for (col in colnames(data)) {
  if (is.numeric(data[[col]]) && sum(as.numeric(data[[col]])) == 0) {
    #cat("Sums to 0: ", col, "\n")
    empty_stats = c(empty_stats, col)
  }
  if (!is.numeric(data[[col]])) {
    #cat("Not numeric: ", col, "\n")
    empty_stats = c(empty_stats, col)
  }
  if (is.numeric(data[[col]]) && sum(as.numeric(data[[col]])) != 0) {
    matches <- unique(grep(paste(skipcolnames,collapse="|"),col,value=TRUE))
    if (length(matches) == 0) {
      plotnames = c(plotnames, col)
    }
  }
}
printf("Dropped %d empty statistic columns", length(empty_stats))

names(data)[names(data)=="RoundRealTime"] <- "Cost"
names(data)[names(data)=="VerifierDelayTime"] <- "Delay"
names(data)[names(data)=="VerifierWaitTime"] <- "Wait"
names(data)[names(data)=="BackTrackCount"] <- "Backtracks"
names(data)[names(data)=="SocketEventSize"] <- "MessageSize"
names(data)[names(data)=="SocketEventSizeBytes"] <- "MessageSizeBytes"
names(data)[names(data)=="InstructionCount"] <- "Insts"


################################################################################
## Create different types of plots over the stat variables
################################################################################

printf("\nGENERATING PLOTS")
################################################################################
if (tag == "ktest-timefix" | tag == "ktest-single-1" | tag == "NDSS2013V2") {

  is_gmail_data = tag == "ktest-timefix" | tag == "ktest-single-1"
  is_games_data = tag == "NDSS2013V2"
  if (is_gmail_data) {
    printf("SSL GMAIL DATA")
  } else if (is_games_data) {
    printf("GAMES DATA")
  } else {
    printf("NOT GAMES OR GMAIL DATA")
  }

  plotwidth = default_plotwidth*0.75
  plotheight = default_plotheight*0.5

  #x="factor(ArrivalBin)"
  x="ArrivalBin"
  xlab="Arrival Time (s)"

  y_axis_list = c("Cost", "Delay")
  ylab_list = c("Verification Cost (s)", "Verification Lag (s)")

  for (m in selected_modes) {
    pdata = subset(data, mode == m)
    # Drop last bin
    #tmp_factors <- unique(factor(pdata$ArrivalBin))
    #maxArrivalBin <- tmp_factors[length(tmp_factors)]
    #pdata = subset(pdata, ArrivalBin != maxArrivalBin)
    for (i in seq(length(y_axis_list))) {
      min_y = as.integer(floor(min(pdata[[y_axis_list[i]]])))
      max_y = as.integer(ceiling(max(pdata[[y_axis_list[i]]])))
      limits_y = c(min_y, max_y)
      #limits_y = c()
      if (is_gmail_data) {
        do_box_plot(y_axis_list[i],x,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"Trace1Only",sep="_"),  plot_data=subset(pdata, trace == 1), grid=FALSE,limits_y=limits_y)
        do_box_plot(y_axis_list[i],x,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"AllButTrace1",sep="_"),plot_data=subset(pdata, trace != 1),grid=FALSE,limits_y=limits_y)
      }
      do_box_plot(y_axis_list[i],x,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"AllTraces",sep="_"),   plot_data=pdata,grid=FALSE,limits_y=limits_y)
    }
  }

  x_alt="SocketEventTimestamp"
  for (m in selected_modes) {
    pdata = subset(data, mode == m)
    for (i in seq(length(y_axis_list))) {
      if (is_gmail_data) {
        do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"Trace1Only",sep="_"),  plot_data=subset(pdata, trace == 1), grid=FALSE)
        do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"AllButTrace1",sep="_"),plot_data=subset(pdata, trace != 1),grid=FALSE)
      }
      do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"AllTraces",sep="_"),   plot_data=pdata,grid=FALSE)
      #do_line_group_plot(y_axis_list[i],x="SocketEventTimestamp",ylab=ylab_list[i],xlab=",plot_data=pdata)
      #do_line_group_plot(y_axis_list[i],x=x_alt,ylab=ylab_list[i],xlab=xlab,plot_data=data)
    }
  }

  if (is_gmail_data) {
    plotwidth = default_plotwidth*0.75
    plotheight = default_plotheight*0.5
    for (i in seq(length(y_axis_list))) {
      tls_tag=paste("Trace1Only","TLS1_3",sep="_")
      tls1_3_data = subset(data, mode=="IDDFS-nAES-1-opt-dropS2C" | mode=="IDDFS-nAES-1-opt-FP128-dropS2C" | mode=="IDDFS-nAES-16-FP128-dropS2C")
      tls1_3_data = subset(tls1_3_data, trace == 1)
      #group_labels = c("NumWorkers=1, No Padding","NumWorkers=1, With Padding","NumWorkers=16, With Padding")
      group_relabels=c("IDDFS-nAES-1-opt-dropS2C.1"="Workers=1, No Padding",
                       "IDDFS-nAES-1-opt-FP128-dropS2C.1"="Workers=1, Padding",
                       "IDDFS-nAES-16-FP128-dropS2C.1"="Workers=16, Padding")
      #group_relabels = c("A", "B", "C")
      #group_labels = c()
      do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag=tls_tag, plot_data=tls1_3_data, grid=FALSE,group_relabels=group_relabels)
    }
  }

  plotwidth = default_plotwidth*0.75
  plotheight = default_plotheight*0.5

  y_axis_list = c("Cost", "Delay")
  ylab_list = c("Verification Cost (s)", "Verification Lag (s)")
  for (i in seq(length(y_axis_list))) {
    if (is_gmail_data) {
      do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag="Trace1Only",  plot_data=subset(data, trace == 1), grid=FALSE, with_points=FALSE)
      do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag="AllButTrace1",plot_data=subset(data, trace != 1), grid=FALSE, with_points=FALSE)
    }
    do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag="AllTraces",   plot_data=data, grid=FALSE,with_points=FALSE)
  }

  x = "SocketEventTimestamp"
  xlab = "Arrival Time (s)"

  ## Generate cumululative data transferred plots
  plotwidth = default_plotwidth*0.75
  plotheight = default_plotheight*0.5

  min_y = as.integer(floor(min(data[["BW"]])))
  max_y = as.integer(ceiling(max(data[["BW"]])))
  pdata = data
  if (is_gmail_data) {
    pdata = subset(data, mode=="IDDFS-nAES-1-opt")
  } else if (is_games_data) {
    pdata = subset(data, mode=="ed-16")
  }
  do_line_group_plot("BW",   x, ylab="Data (KB)", xlab=xlab, plot_data=pdata,min_y=min_y,max_y=max_y)
  do_line_group_plot("BWs2c",x, ylab="Data (KB)", xlab=xlab, plot_data=pdata,min_y=min_y,max_y=max_y)
  do_line_group_plot("BWc2s",x, ylab="Data (KB)", xlab=xlab,plot_data=pdata,min_y=min_y,max_y=max_y)

  plotwidth = default_plotwidth*0.75
  plotheight = default_plotheight*0.5

  # Plot Cost vs MessageSize in best-case run for TLS1_2
  if (is_gmail_data) {
    plotwidth = default_plotwidth*0.75
    plotheight = default_plotheight*0.75

    tls1_2_data = subset(data, mode=="IDDFS-nAES-1-opt")
    do_point_plot("VerifyTimeForSize","MessageSize",ylab="Verification Cost (s)",xlab="Message Size (KB)",tag="TLS1_2",plot_data=tls1_2_data)

    # Plot Cost vs MessageSize in best-case run for TLS1_3
    tls1_3_data = subset(data, mode=="IDDFS-nAES-1-opt-dropS2C" | mode=="IDDFS-nAES-1-opt-FP128-dropS2C" | mode=="IDDFS-nAES-16-FP128-dropS2C")
    do_point_plot("VerifyTimeForSize","MessageSize",ylab="Verification Cost (s)",xlab="Message Size (KB)",tag="TLS1_3",plot_data=tls1_3_data)
  }

} else if (tag == "heartbleed" | tag == "heartbleed-only" | tag == "heartbeat") {
  printf("SSL HEARTBEAT/HEARTBLEED DATA")
  plotwidth = default_plotwidth
  plotheight = default_plotheight
  do_line_plot("Cost")
  #data=subset(data, mode == "IDDFS")
  #if (nrow(data) > 0) {
  #  do_line_plot("RoundRealTime")
  #}
  #quit(status=0)

} else {

  plotwidth = default_plotwidth
  plotheight = default_plotheight
  ##results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)
  ##results = mclapply(plotnames, do_log_box_plot, mc.cores=num_threads)
  ##results = mclapply(c("Delay"), do_max_plot, mc.cores=num_threads)
  ##results = mclapply(c("Delay"), do_last_message_box_plot, mc.cores=num_threads)
  ##results = mclapply(plotnames, do_histogram_plot, mc.cores=num_threads)
  ##results = mclapply(plotnames, do_summary_plot, mc.cores=num_threads)
  #results = mclapply(plotnames, do_mean_plot, mc.cores=num_threads)
  #plotheight = max(default_plotheight,length(unique(data$trace))*heightscalefactor)
  #results = mclapply(plotnames, do_line_alt_plot, mc.cores=num_threads)
  #results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)
  ##x_axis <- "SocketEventSize"
  ##results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)
  ##x_axis <- "RoundNumber"
  #results = mclapply(plotnames, do_logscale_line_plot, mc.cores=num_threads)
  ##results = mclapply(plotnames, do_point_plot, mc.cores=num_threads)

}

plotheight = default_plotheight
plotwidth = default_plotwidth*0.75

# Compute and print summary statistics
if (length(selected_modes) != 0) {
  y_params = c("Cost","Delay","Insts","Wait","Backtracks")
  mode_params = selected_modes
  params = list()

  for (m in seq(length(mode_params))) {
    for (y in seq(length(y_params))) {
      params[[length(params)+1]] = c(mode_params[[m]], y_params[[y]])
    }
  }

  plotwidth = default_plotwidth
  plotheight = default_plotheight/2
  results = mclapply(params, do_box_alt_log_plot, mc.cores=num_threads)
  results = mclapply(params, do_box_alt_plot, mc.cores=num_threads)

  # All Stats: "nbr.val", "min","max","median","mean","var","std.dev","sum")
  stat_names=c("min","max","median","mean","var","std.dev")

  options(scipen=100)
  #options(digits=4)
  allstats = data.frame()
  for (y in seq(length(y_params))) {
    for (m in seq(length(mode_params))) {
      theStat <- y_params[[y]]
      #cat("\nMode: ",mode_params[[m]]," Stat: ", theStat,"\n")
      sdata <- subset(data, mode == mode_params[[m]])
      #print(sdata)
      mdata <- sdata[theStat]
      stats <- stat.desc(mdata)
      print(stats)
      tstats <- t(stats)
      tstats <- tstats[,stat_names,drop=FALSE]
      tstats <- data.frame(t(tstats))
      names(tstats)[names(tstats)==theStat] <- paste(mode_params[[m]], theStat ,sep="_")
      tstats <- t(tstats)

      allstats <- rbind(allstats, tstats)
      #print(tstats)

      # get value of max for this stat
      maxValue <- stats["max", theStat]

      # matching row (if more than one take the first)
      maxRowID = which(sdata[,c(theStat)] == maxValue)[1]

      ## print entire max row
      #cat("\nMax ", theStat," Row:\n")
      #print(sdata[maxRowID,])
    }
  }

  printf("\nSTATISTICS SUMMARY")

  # Output Latex Stat Table
  stat_table <- xtable(t(allstats))
  digits(stat_table) <- 4

  print(allstats)
  sink(paste(save_dir, "stat_table.tex", sep="/"))
  print(stat_table)
  sink()

  # Write all data to csv file
  write.csv(t(allstats), paste(save_dir, "summary_data.csv", sep="/"))
  write.csv(data, paste(save_dir, "processed_data.csv", sep="/"))
}
