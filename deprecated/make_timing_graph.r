#!/usr/bin/Rscript

###############################################################################
# New functions
###############################################################################

### Time summary plot
do_time_summary_all_plot = function() {
  cat("plotting (time_summary_all)\n")
  trace =  paste("time_summary",sep="_")

  file_name = paste(trace, output_filetype, sep=".")
  
  # reformat data  
  mdata1 <- melt(xpilot_data, id=c("mode"),measure=graphTimeStats)
  cdata1 <- cast(mdata1, mode~variable, sum, margins="grand_col")
  
  mdata2 <- melt(tetrinet_data, id=c("mode"),measure=graphTimeStats)
  cdata2 <- cast(mdata2, mode~variable, sum, margins="grand_col")
  
  cdata <- rbind(cdata2, cdata1)
  
  for (statstr in graphTimeStats) {
    cdata[[statstr]] = cdata[[statstr]] / cdata[["(all)"]]
  }
  
  # remove summary column 
  cdata[["(all)"]] <- NULL

  # remove SMT column 
  cdata[["SMT"]] <- NULL

  # construct plot
  p <- ggplot(melt(cdata),aes(x=mode,y=value,fill=factor(variable)))
  p = p + geom_bar(stat="identity", width=.5)
  
  p = p + scale_fill_grey(labels=graphTimeLabels,start = 0.2, end = 0.8)
  
  p = p + theme_bw()
  
  p = p + scale_y_continuous(breaks=c(0.0,0.5,1.0), labels=c("0%","50%","100%"))
  p = p + scale_x_discrete(labels=c("Tetrinet\nDefault","Tetrinet\nHint","XPilot\nDefault","Xpilot\nHint"))

  p = p + theme(axis.title.x=element_blank())
  p = p + ylab("Verification Time")
  p = p + guides(fill = guide_legend(title=NULL,reverse=TRUE))

  p;
  ggsave(paste(save_dir, file_name, sep="/"), width=plotwidth, height=plotheight)

}

###############################################################################
# XPILOT
###############################################################################

source("gsec-support/graph_support.r")

root_dir="/home/rac/research/test.gsec/results/xpilot-ng-x11"

client_type = "xpilot"
selected_modes = c("msg-65536-64-8-t", "hint-65536-64-t")
selected_modes_alt_names = c("Xpilot Default", "Xpilot Hint")
binwidth=100

source("gsec-support/read_data.r")

xpilot_data <- data

###############################################################################
# TETRINET
###############################################################################

source("gsec-support/graph_support.r")

root_dir="/home/rac/research/test.gsec/results/xpilot-ng-x11"

client_type = "tetrinet"
selected_modes = c("msg-65536-64-8-t", "hint-65536-64-t")
selected_modes_alt_names = c("Tetrinet Default", "Tetrinet Hint")
binwidth=10

source("gsec-support/read_data.r")

tetrinet_data <- data


###############################################################################
# Compute number of rows needed for legends
###############################################################################

legend_rows = ceiling(length(unique(factor(data$mode)))/3)

###############################################################################
# Create different types of plots over the stat variables
###############################################################################

root_dir = "./results/all_clients"
output_dir="plots"

save_dir = paste(root_dir, output_dir, format(Sys.time(),"%F-%R"), sep="/")
dir.create(save_dir, recursive=TRUE)

plotheight = default_plotheight/2
plotwidth = default_plotwidth
do_time_summary_all_plot()


