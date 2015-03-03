#!/usr/bin/Rscript

#library(optparse)
#option_list <- list(
#    make_option(c("-v", "--verbose"), action="store_true", default=TRUE,
#        help="Print extra output [default]"),
#    make_option(c("-q", "--quietly"), action="store_false",
#        dest="verbose", help="Print little output"),
#    make_option(c("-c", "--count"), type="integer", default=5,
#        help="Number of random normals to generate [default %default]",
#        metavar="number"),
#    make_option("--generator", default="rnorm",
#        help = "Function to generate random deviates [default \"%default\"]")
#   )
#opt <- parse_args(OptionParser(option_list=option_list))

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

arg_modes=args[-1]

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

selected_modes = arg_modes
selected_modes_alt_names = arg_modes
binwidth=10
#if (client_type == "openssl") {
#  selected_modes = c("naive")
#  selected_modes_alt_names = c("naive")
#  binwidth=10
#  #selected_modes = c("lli", "lli-opt", "ncross-ed-256-16", "ncross-ed-256-1")
#  #selected_modes_alt_names = c("interp","interp-opt", "ED-16", "ED-1")
#  #binwidth=100
#  #printf("client type: %s ", client_type)
#} else if (client_type == "tetrinet") {
#
#  selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg-256-64-8", "hint-256-64")
#  selected_modes_alt_names = c("Default", "Hint", "Default-Coarse", "Hint-Coarse")
#
#  binwidth=10
#} else if (client_type == "xpilot") {
#  #selected_modes = c("msg-65536-64-8", "hint-65536-64", "msg-256-64-8", "hint-256-64")
#  #selected_modes_alt_names = c("Default", "Hint", "Default-Coarse", "Hint-Coarse")
#  selected_modes = c("naive")
#  selected_modes_alt_names = c("naive")
#
#  binwidth=10
#}
num_threads=8

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

# plot data that is numeric and non-zero
plotnames = c()
for (col in colnames(data)) {
  if (is.numeric(data[[col]]) && sum(data[[col]]) != 0) {
    plotnames = c(plotnames, col)
  }
}

if (length(selected_modes) != 0) {
 mode_params = selected_modes_alt_names
 #y_params = c("Time","Delay")
 y_params = c("RoundTime")
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
plotheight = default_plotheight
results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_log_box_plot, mc.cores=num_threads)
#results = mclapply(c("Delay"), do_max_plot, mc.cores=num_threads)
#results = mclapply(c("Delay"), do_last_message_box_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_histogram_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_summary_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_mean_plot, mc.cores=num_threads)
#results = mclapply(plotnames, do_box_plot, mc.cores=num_threads)

printf("Trace count: %d\n", length(unique(data$trace)))
plotheight = max(default_plotheight,length(unique(data$trace))*heightscalefactor)
results = mclapply(plotnames, do_line_alt_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_line_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_logscale_line_plot, mc.cores=num_threads)
results = mclapply(plotnames, do_point_plot, mc.cores=num_threads)

#plotheight = default_plotheight/2
#plotwidth = default_plotwidth*0.75
#do_time_summary_plot()

###############################################################################

