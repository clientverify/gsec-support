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

# binwidth for boxplot graphfs
binwidth=as.numeric(args[3])

## modes to graph
arg_modes=args[-1:-3]

###############################################################################
# Create output dirs
###############################################################################

data_name="data"
output_name="plots"

data_dir = paste(root_dir, data_name, tag, sep="/")
save_dir = paste(root_dir, output_name, tag, format(Sys.time(),"%F-%R"), sep="/")

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

source("gsec-support/read_data.r")

###############################################################################
# Compute number of rows needed for legends
###############################################################################

legend_rows = ceiling(length(unique(factor(data$mode)))/3)

###############################################################################
# Create individual plots for selected modes
###############################################################################

# columns to skip
skipcolnames = c('Bin','trace','RoundNumber','Queries')

# plot data that is numeric and non-zero
plotnames = c()
for (col in colnames(data)) {
  if (is.numeric(data[[col]]) && sum(as.numeric(data[[col]])) == 0) {
    cat("Sums to 0: ", col, "\n")
  }
  if (!is.numeric(data[[col]])) {
    cat("Not numeric: ", col, "\n")
  }
  if (is.numeric(data[[col]]) && sum(as.numeric(data[[col]])) != 0) {
    if (! is.element(col,skipcolnames)) {
      plotnames = c(plotnames, col)
    }
  }
}

################################################################################
## Create different types of plots over the stat variables
################################################################################

if (length(selected_modes) != 0) {
 mode_params = selected_modes_alt_names
 y_params = c("RoundRealTime")
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
}

plotwidth = default_plotwidth
plotheight = default_plotheight

#results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_log_box_plot, mc.cores=num_threads)

#results = mclapply(c("Delay"), do_max_plot, mc.cores=num_threads)
#results = mclapply(c("Delay"), do_last_message_box_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_histogram_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_summary_plot, mc.cores=num_threads)

results = mclapply(plotnames, do_mean_plot, mc.cores=num_threads)

plotheight = max(default_plotheight,length(unique(data$trace))*heightscalefactor)
results = mclapply(plotnames, do_line_alt_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)

#x_axis <- "SocketEventSize"
#results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)
#x_axis <- "RoundNumber"

results = mclapply(plotnames, do_logscale_line_plot, mc.cores=num_threads)

#results = mclapply(plotnames, do_point_plot, mc.cores=num_threads)

plotheight = default_plotheight
plotwidth = default_plotwidth*0.75
do_time_summary_plot()
do_instruction_summary_plot()

################################################################################

if (tag == "heartbleed") {
  debug_printf("tag specific plots")
  plotwidth = default_plotwidth
  plotheight = default_plotheight
  data=subset(data, mode == "IDDFS")
  if (nrow(data) > 0) {
    do_line_plot("RoundRealTime")
  }
  #quit(status=0)
}
