#!/usr/bin/Rscript

args=commandArgs(trailingOnly=TRUE)

###############################################################################
# Source the initial configuration and functions
###############################################################################

source("gsec-support/graph_support.r")

###############################################################################
# Set or get the root_dir
###############################################################################

#root_dir="/home/rac/research/test.gsec/results/xpilot-ng-x11"
#root_dir="/home/rac/research/test.gsec/results/tetrinet-klee"
root_dir="data/results"

# Read data file location from commandline or use hardcoded value
if (length(args) > 0) {
  root_dir = args[1]
}

###############################################################################
# Create output dirs
###############################################################################

data_dir="data"
output_dir="plots"

save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
dir.create(save_dir, recursive=TRUE)

###############################################################################
# Client specific configuration
###############################################################################

client_type = parse_client_type()
if (client_type == "openssl") {
  selected_modes = c("lli", "lli-opt", "ncross-ed-256-16", "ncross-ed-256-1")
  selected_modes_alt_names = c("interp","interp-opt", "ED-16", "ED-1")
  binwidth=100
  printf("client type: %s ", client_type)
} else if (client_type == "tetrinet") {

  selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg-256-64-8", "hint-256-64")
  selected_modes_alt_names = c("Default", "Hint", "Default-Coarse", "Hint-Coarse")

  binwidth=10
} else if (client_type == "xpilot") {
  #selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg-256-64-8", "hint-256-64")
  #selected_modes_alt_names = c("Default", "Hint", "Default-Coarse", "Hint-Coarse")
  selected_modes = c("naive")
  selected_modes_alt_names = c("naive")
  
  binwidth=10
}
num_threads=1

###############################################################################
# Read and parse the data
###############################################################################

source("/playpen/rac/cliver/gsec-support/read_data.r")

###############################################################################
# Compute number of rows needed for legends
###############################################################################

legend_rows = ceiling(length(unique(factor(data$mode)))/3)

###############################################################################
# Create individual plots for selected modes
###############################################################################

plotnames = c(
  #colnames[c(-1)],
  "Time"
  #"EditDistMedoidCount",
  #"ExtraInstructions",
  #"SendInstructions",
  #"Delay"
)

if (length(selected_modes) != 0) {
 mode_params = selected_modes_alt_names
 #y_params = c("Time","Delay")
 y_params = c("Time")
 params = list()
 for (m in seq(length(mode_params))) {
  for (y in seq(length(y_params))) {
   params[[length(params)+1]] = c(mode_params[[m]], y_params[[y]])
  }
 }
 plotwidth = default_plotwidth
 plotheight = default_plotheight/2
 #results = mclapply(params, do_box_alt_log_plot, mc.cores=num_threads)
 results = mclapply(params, do_box_alt_plot, mc.cores=num_threads)
}

###############################################################################
# Create different types of plots over the stat variables
###############################################################################

plotwidth = default_plotwidth
plotheight = default_plotheight*2
results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_log_box_plot, mc.cores=num_threads)
#results = mclapply(c("Delay"), do_max_plot, mc.cores=num_threads)
#results = mclapply(c("Delay"), do_last_message_box_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_histogram_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_summary_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_mean_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)

plotheight = length(unique(data$trace))*heightscalefactor
results = mclapply(plotnames, do_line_alt_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_logscale_line_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_point_plot, mc.cores=num_threads)

plotheight = default_plotheight/2
plotwidth = default_plotwidth*0.75
#do_time_summary_plot()

###############################################################################

