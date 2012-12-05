
# Read the timestamp data
read_timestamps()

# Read cliver logs
read_all_data()

# Convert list of data matrices to a single data frame
data = as.data.frame(do.call(rbind, all_data))
rm(all_data)
colnames(data) = data_frame_col_names

# Retrace integer factors to string names
for (i in seq(length(modes))) {
  data$mode[data$mode == i] <- get_mode_str(i)
}

# Remove Message times from list of time stats to graph
graphTimeStats = timeStats[c(-1,-2,-3,-4)]

# Compute OtherTime (total minus all other time stats)
otherTime = data$TimeReal + data$TimeSys
for (t in graphTimeStats) {
  otherTime = otherTime - data[t]
}
data$OtherTime = otherTime

# Compute additional stats and sub stat times
data$ExtraInstructions = data$Instructions - data$ValidPathInstructions
data$SendInstructions = data$Instructions - data$RecvInstructions
data$Time = data$TimeReal - data$EdDistHintTime - data$EdDistStatTime
data$SolverTime = data$SolverTime - data$STPTime - data$CEXTime
data$EdDistBuildTime = data$EdDistBuildTime - data$EdDistHintTime
data$EdDistTime = data$EdDistTime - data$EdDistStatTime

# Scale time stats from microsecnds to seconds
for (tstat in c(timeStats,"Delay")) {
  data[tstat] = data[tstat] / 1000000.0
}

# Grouped Time stats
data$ConstraintOpt = data$SolverTime + data$CEXTime
data$SMT = data$STPTime
data$EditDistance = data$EdDistTime + data$EdDistBuildTime + data$ExecTreeTime
data$PathSelection = data$SearcherTime
data$EquivalentStateDetection = data$MergeTime
data$KLEE = data$TimeReal + data$TimeSys - data$ConstraintOpt - data$SMT - data$EditDistance - data$PathSelection - data$EdDistStatTime- data$EdDistHintTime - data$EquivalentStateDetection

graphTimeStats = c("KLEE","PathSelection","EditDistance","EquivalentStateDetection", "ConstraintOpt","SMT")
graphTimeLabels = c("Executing insts. in KLEE","Operations on Live","Computing Edit Distance","Equiv. State Detection", "Constraint Solving")

# Trim data by start and min Messages 
data = subset(data, Message > start_Message & Message <= as.integer(floor(min_size/binwidth))*binwidth)

# Remove erronous traces
data = subset(data, trace != 19)


