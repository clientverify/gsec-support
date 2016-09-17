#!/usr/bin/Rscript

args <- commandArgs(trailingOnly=TRUE)

###############################################################################
# Source the initial configuration and functions
###############################################################################

source("gsec-support/graph_support.r")

###############################################################################
# Set or get the root_dir
###############################################################################

# Read data file location from commandline (e.g., data/results/cross-client)
root_dir <- args[1]

# run_prefix (e.g., "2016-09-17.16:15:01")
run_prefix <- args[2]

## modes to graph (e.g., IDDFS-nAES-1-opt-dropS2C ...)
arg_modes <- args[-1:-2]
selected_modes = arg_modes
selected_modes_alt_names = arg_modes

num_threads <- 64

###############################################################################
# Create output dirs
###############################################################################

data_name <- "data"
output_name <- "plots"

data_dir <- paste(root_dir, "data", run_prefix, sep="/")
save_dir <- paste(root_dir, "plots", run_prefix, sep="/")

###############################################################################
# Read and parse the data
###############################################################################

printf("\nReading processed data from all clients")
alldata <- read_processed_data(data_dir)
client_datatag_pairs <- unique(alldata[,c("Client","DataTag")])
printf("%d data sets collected. Client/DataTag pairs:",
       nrow(client_datatag_pairs))
print(client_datatag_pairs)

###############################################################################
# Compute number of rows needed for legends
###############################################################################

legend_rows <- ceiling(length(unique(factor(alldata$mode)))/3)

###############################################################################
# Create individual plots for selected modes
###############################################################################

# columns to skip
skipcolnames = c('Bin','trace','RoundNumber','Queries','Quer','SocketEvent')

# plot data that is numeric and non-zero
plotnames = c()
empty_stats = c()
for (col in colnames(alldata)) {
  if (is.numeric(alldata[[col]]) && sum(as.numeric(alldata[[col]])) == 0) {
    #cat("Sums to 0: ", col, "\n")
    empty_stats = c(empty_stats, col)
  }
  if (!is.numeric(alldata[[col]])) {
    #cat("Not numeric: ", col, "\n")
    empty_stats = c(empty_stats, col)
  }
  if (is.numeric(alldata[[col]]) && sum(as.numeric(alldata[[col]])) != 0) {
    matches <- unique(grep(paste(skipcolnames,collapse="|"),col,value=TRUE))
    if (length(matches) == 0) {
      plotnames = c(plotnames, col)
    }
  }
}
printf("Dropped %d empty statistic columns", length(empty_stats))


################################################################################
## Create different types of plots over the stat variables
################################################################################

printf("\nGENERATING PLOTS")
################################################################################
for (tag in unique(client_datatag_pairs$DataTag)) {

  is_gmail_data = tag == "ktest-timefix" | tag == "ktest-single-1"
  if (is_gmail_data) {
    printf("SSL GMAIL DATA")
  } else {
    printf("NOT GMAIL DATA")
  }

  plotwidth = default_plotwidth
  plotheight = default_plotheight*(2.0)/(3.0)

  #x="factor(ArrivalBin)"
  x="ArrivalBin"
  xlab="Arrival Time (s)"

  y_axis_list = c("Cost", "Delay")
  ylab_list = c("Verification Cost (s)", "Verification Lag (s)")

  for (m in selected_modes) {
    pdata = subset(alldata, mode == m & DataTag == tag)
    for (i in seq(length(y_axis_list))) {
      min_y = as.integer(floor(min(pdata[[y_axis_list[i]]])))
      max_y = as.integer(ceiling(max(pdata[[y_axis_list[i]]])))
      limits_y = c(min_y, max_y)
      if (is_gmail_data) {
        do_box_plot_xc(y_axis_list[i], x, ylab=ylab_list[i], xlab=xlab,
                       tag=paste(tag, m, "Trace1Only", sep="_"),
                       plot_data=subset(pdata, trace == 1),
                       full_data=alldata,
                       grid=FALSE, limits_y=limits_y)
        do_box_plot_xc(y_axis_list[i], x, ylab=ylab_list[i], xlab=xlab,
                       tag=paste(tag, m, "AllButTrace1", sep="_"),
                       plot_data=subset(pdata, trace != 1),
                       full_data=alldata,
                       grid=FALSE, limits_y=limits_y)
      }
      do_box_plot_xc(y_axis_list[i], x, ylab=ylab_list[i], xlab=xlab,
                     tag=paste(tag, m,"AllTraces",sep="_"),
                     plot_data=pdata,
                     full_data=alldata,
                     grid=FALSE, limits_y=limits_y)
    }
  }

  next  # skip others for now

  x_alt="SocketEventTimestamp"
  for (m in selected_modes) {
    pdata = subset(alldata, mode == m & DataTag == tag)
    for (i in seq(length(y_axis_list))) {
      if (is_gmail_data) {
        do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"Trace1Only",sep="_"),  plot_data=subset(pdata, trace == 1), grid=FALSE)
        do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag=paste(m,"AllButTrace1",sep="_"),plot_data=subset(pdata, trace != 1),grid=FALSE)
      }
      do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag=paste(tag, m,"AllTraces",sep="_"), plot_data=pdata,grid=FALSE)
    }
  }

  if (is_gmail_data) {
    plotwidth = default_plotwidth*0.75
    plotheight = default_plotheight*0.5
    for (i in seq(length(y_axis_list))) {
      tls_tag=paste("Trace1Only","TLS1_3",sep="_")
      tls1_3_data = subset(alldata,
         (mode=="IDDFS-nAES-1-opt-dropS2C" |
          mode=="IDDFS-nAES-1-opt-FP128-dropS2C" |
          mode=="IDDFS-nAES-16-FP128-dropS2C") &
         (DataTag == tag))
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
      do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag="Trace1Only",  plot_data=subset(alldata, trace == 1 & DataTag == tag), grid=FALSE, with_points=FALSE)
      do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag="AllButTrace1",plot_data=subset(alldata, trace != 1 & DataTag == tag), grid=FALSE, with_points=FALSE)
    }
    do_line_group_plot(y_axis_list[i],x_alt,ylab=ylab_list[i],xlab=xlab,tag="AllTraces",   plot_data=subset(alldata, DataTag == tag), grid=FALSE,with_points=FALSE)
  }

  x = "SocketEventTimestamp"
  xlab = "Arrival Time (s)"

  ## Generate cumulative data transferred plots
  plotwidth = default_plotwidth*0.75
  plotheight = default_plotheight*0.5

  min_y = as.integer(floor(min(alldata[["BW"]])))
  max_y = as.integer(ceiling(max(alldata[["BW"]])))
  pdata = alldata
  if (is_gmail_data) {
    pdata = subset(alldata, mode == "IDDFS-nAES-1-opt" & DataTag == tag)
  } else if (is_games_data) {
    pdata = subset(alldata, mode == "ed-16" & DataTag == tag)
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

    tls1_2_data = subset(alldata, mode=="IDDFS-nAES-1-opt" & DataTag == tag)
    do_point_plot("VerifyTimeForSize","MessageSize",ylab="Verification Cost (s)",xlab="Message Size (KB)",tag="TLS1_2",plot_data=tls1_2_data)

    # Plot Cost vs MessageSize in best-case run for TLS1_3
    tls1_3_data = subset(alldata, (mode=="IDDFS-nAES-1-opt-dropS2C" | mode=="IDDFS-nAES-1-opt-FP128-dropS2C" | mode=="IDDFS-nAES-16-FP128-dropS2C") & (DataTag == tag))
    do_point_plot("VerifyTimeForSize","MessageSize",ylab="Verification Cost (s)",xlab="Message Size (KB)",tag="TLS1_3",plot_data=tls1_3_data)
  }

}
