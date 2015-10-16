library(ggplot2)
d <- read.csv("./data/coreutils/recent/coreutils.csv")
ggplot(d, aes(threads,paths)) + geom_line() + geom_point() + scale_x_discrete(breaks=d$threads) + theme_bw() + facet_grid(search ~ bc)
dprintf <- subset(d, bc == "printf" & search == "nurs:covnew")
dprintf$instructions = dprintf$instructions * 1
p <- ggplot(dprintf, aes(threads,paths)) + geom_line() + geom_point() 
p <- p + scale_x_discrete(breaks=dprintf$threads) + theme_bw() + xlab("Threads") + ylab("Instructions")
p;
ggsave("coreutils_paths.eps",width=6,height=3)


