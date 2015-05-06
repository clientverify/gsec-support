
# Read the timestamp data
#read_timestamps()

data = data.frame()

# Read cliver logs
#read_all_data()
read_csv_data()
#stop("quitin' early")

## Convert list of data matrices to a single data frame
#data = as.data.frame(do.call(rbind, all_data))
#rm(all_data)
#colnames(data) = data_frame_col_names

# Retrace integer factors to string names
for (i in seq(length(modes))) {
  data$mode[data$mode == i] <- get_mode_str(i)
}

# Scale time stats from microsecnds to seconds
for (col in colnames(data)) {
  if (grepl("Time", col)) {
    cat("Scaling Time Stat: ", col, "\n")
    data[col] = data[col] / 1000000.0
  }
}

graphTimeStats = c()
for (col in colnames(data)) {
  if (grepl("Time", col)) {
    if (!grepl("RoundUser", col) & !grepl("RoundSys", col)
        & !grepl("RoundReal",col) & !grepl("Delay",col) & !grepl("Timestamp",col)) {
      graphTimeStats = c(graphTimeStats, col)
    }
  }
}

data$KLEETime = data$RoundRealTime
for (stat in graphTimeStats) {
  cat("subtracting :", stat, "\n")
  data$KLEETime = data$KLEETime - data[, stat]
}
graphTimeStats = c(graphTimeStats, 'KLEETime')
graphTimeLabels = graphTimeStats

graphInstructionStats = c()
for (col in colnames(data)) {
  if (grepl("InstructionCount", col)) {
    graphInstructionStats = c(graphInstructionStats, col)
  }
}
graphInstructionLabels = graphInstructionStats


#graphTimeStats = c("KLEE","PathSelection","EditDistance","EquivalentStateDetection", "ConstraintOpt","SMT")
#graphTimeLabels = c("Executing insts. in KLEE","Operations on Live","Computing Edit Distance","Equiv. State Detection", "Constraint Solving")
#
#graphTimeStats = c("RoundRealTime","SolverTime","ExecTreeTime","MergerTime", "SearcherTime","QueryTime")
#graphTimeLabels= c("RoundRealTime","SolverTime","ExecTreeTime","MergerTime", "SearcherTime","QueryTime")

############### regen and uncomment XXX
# Compute additional stats and sub stat times
#data$ExtraInstructionCount = data$InstructionCount - data$ValidPathInstructionCount
#data$SendInstructionCount = data$InstructionCount - data$RecvInstructionCount
#data$EditDistTotalTime = data$EditDistTime + data$EditDistBuildTime + data$ExecTreeTime
############### regen and uncomment XXX



#data$Time = data$TimeReal - data$EdDistHintTime - data$EdDistStatTime
#data$SolverTime = data$SolverTime - data$STPTime - data$CEXTime
#data$EdDistBuildTime = data$EdDistBuildTime - data$EdDistHintTime
#data$EdDistTime = data$EdDistTime - data$EdDistStatTime

## Grouped Time stats
#data$ConstraintOpt = data$SolverTime + data$CEXTime
#data$SMT = data$STPTime
#data$PathSelection = data$SearcherTime
#data$EquivalentStateDetection = data$MergeTime
#data$KLEE = data$TimeReal + data$TimeSys - data$ConstraintOpt - data$SMT - data$EditDistance - data$PathSelection - data$EdDistStatTime- data$EdDistHintTime - data$EquivalentStateDetection
#graphTimeStats = c("KLEE","PathSelection","EditDistance","EquivalentStateDetection", "ConstraintOpt","SMT")
#graphTimeLabels = c("Executing insts. in KLEE","Operations on Live","Computing Edit Distance","Equiv. State Detection", "Constraint Solving")

## Trim data by start and min Messages
##data = subset(data, Message > start_Message & Message <= as.integer(floor(min_size/binwidth))*binwidth)

## Remove first round of data (startup cost)
data = subset(data, RoundNumber > 1)
