# libraries --------------------------------------------------------------------
library(cmdstanr)
library(ggplot2)
library(bayesplot)
library(posterior)
library(ggdist)
library(tidyverse)
library(cowplot) # for plotting grids of small plots
library(psych) # for independent variables correlation plot


# modelling and data prep ------------------------------------------------------
# compile the model
model <- cmdstan_model("../models/poisson.stan")

# load data
data <- read.csv("../data/football.csv", sep=";")

# drop missing data
data <- drop_na(data)

# add ID column
data$ID <- seq.int(nrow(data))

# prep data
df_X <- data %>% select(-INFO_Date, -INFO_Competition, -INFO_TeamH, -INFO_TeamA, -Y_FTHG, -Y_FTAG)

# center and standardize
X <- scale(df_X)

# plot correlation of independent variables
pairs.panels(X, 
             method = "pearson", # correlation method
             hist.col = "skyblue",
             density = TRUE,  # show density plots
             ellipses = TRUE # show correlation ellipses
)

y <- data$Y_FTHG # home goals
#y <- data$Y_FTAG # away goals
stan_data <- list(n=nrow(data), m=ncol(X), X=X, y=y)

# fit
fit <- model$sample(
  data = stan_data,
  parallel_chains = 4
)


# diagnostics ------------------------------------------------------------------
# traceplot for beta parameters
mcmc_trace(fit$draws("beta"))

# summary of betas
fit$summary("beta")


# analysis ---------------------------------------------------------------------
# extract parameters
df_alpha <- as_draws_df(fit$draws("alpha"))
df_beta <- as_draws_df(fit$draws("beta"))
df_lambda <-as_draws_df(fit$draws("lambda"))
df_pred <-as_draws_df(fit$draws("pred"))


# plot betas -------------------------------------------------------------------
# remove unwanted columns
df_beta <- df_beta %>% select(-.chain, -.iteration, -.draw)

# rename for ease of addressing
colnames(df_beta) <- colnames(df_X)

# to long format
df_beta <- df_beta %>% gather(Beta, Value)

# plot
ggplot(data = df_beta, aes(x = Value, y = Beta)) +
  stat_eye(fill = "skyblue", alpha = 0.75)


# compare lambda vs actual scored goals ----------------------------------------
df_lambda <- df_lambda %>% select(-.chain, -.iteration, -.draw)
df_lambda_goals <- data.frame(Goals = data$Y_FTHG, Lambda = colMeans(df_lambda))

# x axis labels
goals <- sort(unique(df_lambda_goals$Goals))

# plot
ggplot(data = df_lambda_goals, aes(x = Goals, y = Lambda)) +
  geom_jitter(alpha=0.3, size=2, shape=16) +
  scale_x_continuous("Goals", breaks=goals, labels=goals)


# compare predictions vs home goals for Atletico Madrid ------------------------
df_pred <- df_pred %>% select(-.chain, -.iteration, -.draw)

# compare last 9 games in dataset
df_am <- data %>% filter(INFO_TeamH == "Ath Madrid")
df_am <- tail(df_am, 9)

# select appropriate predictions
df_pred <- df_pred[, df_am$ID]

# create plots
plots <- NULL
for (i in 1:9) {
  df_preds <- data.frame(x=df_pred %>% nth(i))
  df_counts <- df_preds %>% count(x)
  q25 <- quantile(df_preds$x, 0.05)
  q75 <- quantile(df_preds$x, 0.75)
  
  p <- ggplot(data = df_counts, aes(x = x, y = n)) +
    geom_bar(stat="identity", color="skyblue", fill="skyblue", alpha = 0.75) +
    geom_vline(xintercept=df_am[i,]$Y_FTHG, color = "grey50", size = 2) +
    geom_vline(xintercept=q25, color = "grey25", size = 1, linetype = "dashed") +
    geom_vline(xintercept=q75, color = "grey25", size = 1, linetype = "dashed") +
    scale_x_continuous("Goals", breaks=df_counts$x, labels=df_counts$x, limits=c(-0.5,6.5)) +
    ylim(0, 1500) +
    ylab("Count") +
    ggtitle(df_am[i,]$INFO_TeamA) +
    theme(plot.title = element_text(hjust = 0.5))
    
  plots[[i]] <- p
}

# plot the grid
plot_grid(plotlist=plots, ncol=3, nrow=3, scale=0.9)
