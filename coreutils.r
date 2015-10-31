#!/usr/bin/Rscript

library(ggplot2)
library(xtable)
d <- read.csv("./data/coreutils/recent/coreutils.csv")
ggplot(d, aes(threads,paths)) + geom_line() + geom_point() + scale_x_discrete(breaks=d$threads) + theme_bw() + facet_grid(search ~ bc)
dprintf <- subset(d, bc == "printf" & search == "nurs:covnew")
dprintf$instructions = dprintf$instructions * 1
p <- ggplot(dprintf, aes(threads,paths)) + geom_line() + geom_point() 
p <- p + scale_x_discrete(breaks=dprintf$threads) + theme_bw() + xlab("Threads") + ylab("Instructions")
p;
print(xtable(t(dprintf)))
ggsave("coreutils_paths.png",width=3,height=3)


