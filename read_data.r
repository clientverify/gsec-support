
# Global data frame object which will contain all input data
data = data.frame()

# Read cliver logs
read_csv_data()

# Rename integer factors to string names
for (i in seq(length(modes))) {
  data$mode[data$mode == i] <- get_mode_str(i)
}

# Scale time stats from microsecnds to seconds
for (col in colnames(data)) {
  if (grepl("Time", col)) {
    #debug_printf("Scaling Time Stat: %s", col)
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
  data$KLEETime = data$KLEETime - data[, stat]
}
graphTimeStats = c(graphTimeStats, 'KLEETime')
graphTimeLabels = graphTimeStats

# Compute additional stats and sub stat times
data$ExtraInstructionCount = data$InstructionCount - (data$ValidPathInstructionCountPassOne + data$ValidPathInstructionCount)
data$RoundRealTimeOpt = data$RoundRealTime - data$BindingsSolveTime
data$RoundRealTimePerInst = data$RoundRealTime / data$InstructionCount

graphInstructionStats = c()
for (col in colnames(data)) {
  if (grepl("InstructionCount", col)) {
    graphInstructionStats = c(graphInstructionStats, col)
  }
}
graphInstructionLabels = graphInstructionStats

## Convert socket event size data from bytes to kilobytes
data$SocketEventSizeBytes = data$SocketEventSize
data$SocketEventSize = data$SocketEventSize / 1024
data$BW= data$BW / 1024
data$BWs2c= data$BWs2c / 1024
data$BWc2s= data$BWc2s / 1024

### Old stats conversion ###
#graphTimeStats = c("KLEE","PathSelection","EditDistance","EquivalentStateDetection", "ConstraintOpt","SMT")
#graphTimeLabels = c("Executing insts. in KLEE","Operations on Live","Computing Edit Distance","Equiv. State Detection", "Constraint Solving")
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


