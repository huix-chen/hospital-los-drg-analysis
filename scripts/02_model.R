# 02_model.R
# Mixed-effects modelling of length of stay (LOS ~ (1|DRG) + fixed effects),
# plus model comparison and sensitivity analyses. Run from `portfolio/`
# after 01_eda.R has produced data/df_clean.rds.

# Libraries
library(dplyr)
library(ggplot2)
library(MASS)   # for glm.nb (Negative Binomial)
library(lme4)   # for lmer (1 | DRG)
`%||%` <- function(a, b) if (!is.null(a)) a else b  # lme4 bug workaround
library(performance)
library(parameters)
library(lmerTest)
library(patchwork)
# 变量              理由
# age              年龄越大住得越久（EDA验证）
# num_diagnoses    并发症越多越复杂（EDA验证）
# urgency_label    急诊比择期住得更久（EDA验证）
# care_type_label  Palliative/Newborn结构性长住（EDA验证）
# drg_chapter      body system（AR-DRG第1位字母，约23类）
# drg_partition    DRG内复杂度分层（A/B/C/Z）
# admission_period 晚上入院多住一天（EDA验证）
# referral_label   Transfer in更复杂（EDA验证）
# insurer_group    无保险病人LOS更长（EDA验证）
# prearranged_overnight  行政安排（EDA验证）

# Load cleaned data from EDA
df_clean <- readRDS("data/df_clean.rds")

df_model <- df_clean %>%
  mutate(
    transfer_in     = as.integer(!is.na(TransferInProviderNumber)),
    drg_chapter     = substr(DRG, 1, 1),
    drg_partition   = substr(DRG, 4, 4),
    had_theatre     = as.integer(!is.na(TheatreMinutes) & TheatreMinutes > 0),
    theatre_min     = ifelse(is.na(TheatreMinutes) | TheatreMinutes == 0, 0,
                             TheatreMinutes),
    referral_label  = relevel(referral_label, ref = "Medical Practitioner"),
    urgency_label   = relevel(urgency_label,  ref = "Emergency"),
    admission_period = factor(admission_period,
                              levels = c("Morning", "Afternoon", "Evening", "Night"))
  ) %>%
  filter(!is.na(age), !is.na(sex_label), !is.na(urgency_label),
         !is.na(care_type_label), !is.na(num_diagnoses), !is.na(DRG),
         !is.na(referral_label), !is.na(admission_period))

cat("Modelling dataset:", nrow(df_model), "rows\n")

table(table(df_model$DRG))
#(1 | DRG) 的原理： 
# 把DRG当作random effect，小样本DRG（1-5人）的估计值被自动拉向全局均值（shrinkage），
# 大样本DRG（328人、518人）几乎不受影响。等于内置正则化，解决稀疏问题。

# ── DRG structure sanity check ────────────────────────────────────────────────
cat("\nDRG chapter distribution:\n")
df_model %>%
  count(drg_chapter, sort = TRUE) %>%
  print(n = 30)

cat("\nDRG partition distribution:\n")
print(table(df_model$drg_partition))

cat("有手术记录:", sum(df_model$had_theatre), "人 /", nrow(df_model), "\n")

# 同一DRG内，theatre_min和LOS的相关性
  df_model %>%
    filter(had_theatre == 1) %>%
    group_by(DRG) %>%
    filter(n() >= 10) %>%
    summarise(r = cor(theatre_min, log(los)), n = n(), .groups = "drop") %>%
    summarise(meidan_r = round(median(r, na.rm = TRUE), 3),
              n_drg  = n())
# ── DRG APPROACH COMPARISON (LM only) ────────────────────────────────────────
base_vars <- "age + sex_label + urgency_label + care_type_label +
  num_diagnoses + insurer_group + prearranged_overnight +
  referral_label + admission_period"

cat("\nLOS range check:\n")
cat(sprintf("  min = %d,  zeros = %d\n",
            min(df_model$los), sum(df_model$los == 0)))

lm_drg_full <- lm(as.formula(paste("log(los) ~", base_vars, "+ DRG")),
                  data = df_model) # 过拟合，多用了 473 个参数，log-likelihood 提升了 (946+456)/2 = 701
lmer_re     <- lmer(as.formula(paste("log(los) ~", base_vars, "+ (1 | DRG)")),
                    data = df_model, REML = FALSE) # 暂时选这个
lm_no_drg   <- lm(as.formula(paste("log(los) ~", base_vars)),
                  data = df_model)

drg_compare <- data.frame(
  Model        = c("Full DRG (fixed)", "Random DRG (1|DRG)", "No DRG"),
  n_fix_params = c(length(coef(lm_drg_full)),
                   length(fixef(lmer_re)),
                   length(coef(lm_no_drg))),
  AIC          = round(c(AIC(lm_drg_full),
                         AIC(lmer_re),
                         AIC(lm_no_drg)), 1),
  R2           = round(c(summary(lm_drg_full)$adj.r.squared,
                         as.numeric(r2(lmer_re)$R2_conditional),
                         summary(lm_no_drg)$adj.r.squared), 3),
  R2_note      = c("adj R2", "conditional R2", "adj R2"),
  RMSE         = round(c(
    sqrt(mean((df_model$los - exp(predict(lm_drg_full)))^2)),
    sqrt(mean((df_model$los - exp(predict(lmer_re)))^2)),
    sqrt(mean((df_model$los - exp(predict(lm_no_drg)))^2))
  ), 3)
)

cat("\n── DRG Approach Comparison ──\n")
print(drg_compare)

# ── MODEL A: Linear Mixed Model  lmer + (1 | DRG) ────────────────────────────
summary(lm_drg_full) # Adjusted R² = 0.66

summary(lmer_re)
r2(lmer_re) # Conditional R2: 0.628, Random effect 成功保留了 DRG 的解释能力。
#Marginal R² = 0.271, 因为DRG很重要
icc(lmer_re) # 49% 的 variance 来自 DRG。
VarCorr(lmer_re) # 知道病人是哪个 DRG，和知道病人的个人因素（年龄、并发症等），对预测 LOS 的帮助一样大
summary(lmer_re)$coef
confint(lmer_re)

# Residuals vs Fitted	线性 + 等方差	随机散点，无扇形/曲线
# Q-Q of residuals	残差正态性	点贴近对角线
# Q-Q of random effects	DRG随机效应正态性（lmer假设）	点贴近对角线
# Scale-Location	等方差	红线水平

diag_df <- data.frame(
  fitted = fitted(lmer_re),
  resid  = resid(lmer_re)
)
re_df <- data.frame(re = ranef(lmer_re)$DRG[[1]])
binned_resid <- diag_df |>
  mutate(bin = ntile(fitted, 50)) |>
  group_by(bin) |>
  summarise(
    fitted_mean = mean(fitted, na.rm = TRUE),
    resid_mean  = mean(resid, na.rm = TRUE),
    resid_se    = sd(resid, na.rm = TRUE) / sqrt(n()),
    n = n(),
    .groups = "drop"
  ) |>
  mutate(
    lower = resid_mean - 1.96 * resid_se,
    upper = resid_mean + 1.96 * resid_se
  )

p_resid_binned <- ggplot(binned_resid, aes(x = fitted_mean, y = resid_mean)) +
  geom_hline(yintercept = 0, colour = "red", linewidth = 0.5) +
  geom_errorbar(aes(ymin = lower, ymax = upper), width = 0, alpha = 0.5) +
  geom_point(size = 1.8) +
  geom_smooth(se = FALSE, linewidth = 0.6) +
  labs(
   title = "Binned Residuals vs Fitted Values",
    x = "Mean fitted value",
    y = "Mean residual"
  ) +
  theme_minimal()

p_qq <- ggplot(diag_df, aes(sample = resid)) +
  stat_qq(alpha = 0.3, size = 0.8) + stat_qq_line(color = "red") +
  labs(title = "Q-Q: Residuals", x = "Theoretical", y = "Sample")

# heteroscedasticity
p_qq_re <- ggplot(re_df, aes(sample = re)) +
  stat_qq(alpha = 0.5) + stat_qq_line(color = "red") +
  labs(title = "Q-Q: DRG Random Effects", x = "Theoretical", y = "Sample")

binned_scale <- diag_df |>
  mutate(sqrt_abs_resid = sqrt(abs(resid)),
         bin = ntile(fitted, 50)) |>
  group_by(bin) |>
  summarise(fitted_mean = mean(fitted),
            scale_mean  = mean(sqrt_abs_resid),
            .groups = "drop")

p_scale <- ggplot(binned_scale, aes(fitted_mean, scale_mean)) +
  geom_point(size = 1.8) +
  geom_smooth(se = FALSE, color = "red", linewidth = 0.6) +
  labs(title = "Scale-Location (binned)", x = "Mean fitted value",
       y = "Mean √|Residual|") +
  theme_minimal()

diag_plot <- (p_resid_binned | p_qq) / (p_qq_re | p_scale)
ggsave("plots/p_lmer_diagnostics.png", diag_plot, width = 10, height = 8)

# Stepwise variable selection (backward, lmerTest)，一个都删不了
# lmer_re 是 full model；lmerTest::step() 用 F-test (Satterthwaite df) 逐步剔除变量
lmer_full <- lmerTest::lmer(log(los) ~ age + sex_label + urgency_label +
                              care_type_label + num_diagnoses + referral_label+ 
                              insurer_group + prearranged_overnight  +
                              admission_period + (1 | DRG),
                            data = df_model, REML = FALSE)
lmer_full

cat("\n── lmerTest stepwise (backward) ──\n")
step_result <- lmerTest::step(lmer_full, direction = "backward", reduce.random = FALSE)
print(step_result)

# num_diagnoses F = 1063，最强，远超其他
# (1|DRG) Chi² = 3132，DRG 随机效应极显著，必须保留
# insurer_group p = 0.016，最弱，10个 level 只勉强显著——这个可以在 SA 里测一下去掉会怎样
# prearranged_overnight p = 0.010，也比较弱，同样可以做 SA

cat("\nFinal model summary:\n")
summary(lmer_full)
r2(lmer_full)

# ── Multicollinearity check (VIF) ─────────────────────────────────────────────
cat("\n── VIF: multicollinearity check ──\n")
print(check_collinearity(lmer_full))
# VIF < 5 = ok, 5-10 = warning, > 10 = serious
# 它们之间有临床逻辑关联——A&E 转来的病人大概率是急诊，GP 转来的大概率是择期。
#所以两个变量不完全独立，会互相"解释"一部分方差。
#但 3.64 < 5，远低于警戒线。之前删掉 transfer_in 是正确的—
#它和 referral_label 的 VIF 等于无穷大（完全共线），才是真正的问题。现在剩下的全部可接受。

# ── Continuous variable correlation plot ──────────────────────────────────────
library(corrplot)
cont_cor <- df_model %>%
  dplyr::select(los, age, num_diagnoses) %>%
  cor(use = "complete.obs")

png("plots/p_cor_continuous.png", width = 600, height = 500)
corrplot(cont_cor, method = "number", type = "upper",
         tl.col = "black", tl.srt = 45,
         title = "Correlation: continuous variables", mar = c(0, 0, 2, 0))
dev.off()

# ── SENSITIVITY ANALYSES ─────────────────────────────────────────────────────

# SA1: add ccu_flag
lmer_sa1 <- lmerTest::lmer(
  log(los) ~ age + sex_label + urgency_label + care_type_label +
    num_diagnoses + insurer_group + prearranged_overnight +
    referral_label + admission_period + ccu_flag + (1 | DRG),
  data = df_model, REML = FALSE
)

# SA2: merge rare DRGs (< 10 patients) into "Other"
rare_drgs <- names(which(table(df_model$DRG) < 10))
cat(sprintf("\nSA2: %d rare DRGs (< 10 patients) merged into 'Other'\n",
            length(rare_drgs)))
df_sa2 <- df_model %>%
  mutate(DRG_g = ifelse(DRG %in% rare_drgs, "Other", as.character(DRG)))

lmer_sa2 <- lmerTest::lmer(
  log(los) ~ age + sex_label + urgency_label + care_type_label +
    num_diagnoses + insurer_group + prearranged_overnight +
    referral_label + admission_period + (1 | DRG_g),
  data = df_sa2, REML = FALSE
)

# SA3: remove prearranged_overnight
lmer_sa3 <- lmerTest::lmer(
  log(los) ~ age + sex_label + urgency_label + care_type_label +
    num_diagnoses + insurer_group +
    referral_label + admission_period + (1 | DRG),
  data = df_model, REML = FALSE
)

# SA4: Negative Binomial GLM (glm.nb + fixed DRG)
# glmmTMB with (1|DRG) fails due to sparse DRG groups;
# glm.nb with fixed DRG still tests NB vs log-normal distribution assumption
sa4_formula <- los ~ age + sex_label + urgency_label + care_type_label +
  num_diagnoses + DRG + insurer_group + prearranged_overnight +
  referral_label + admission_period

poisson_sa4 <- glm(
  sa4_formula,
  family = poisson(link = "log"),
  data = df_model
)

nb_sa4 <- glm.nb(
  sa4_formula,
  data = df_model
)

# ── SA4: NB model diagnostics ────────────────────────────────────────────────
# For explanatory modelling, SA4 is mainly a distributional sensitivity check:
# if Poisson is overdispersed but NB is not, NB is a better count-model assumption.
cat("\n── SA4: Poisson vs Negative Binomial diagnostics ──\n")
cat("\nPoisson overdispersion check:\n")
print(check_overdispersion(poisson_sa4))

cat("\nSA4 NB theta (dispersion):", round(nb_sa4$theta, 3), "\n")
cat("\nNegative Binomial overdispersion check:\n")
print(check_overdispersion(nb_sa4))

sa4_count_fit <- data.frame(
  Model = c("Poisson", "Negative Binomial"),
  AIC   = round(c(AIC(poisson_sa4), AIC(nb_sa4)), 1)
)
print(sa4_count_fit, row.names = FALSE)

key_vars <- c("age", "num_diagnoses",
              "urgency_labelElective", "urgency_labelNot assigned",
              "referral_labelTransfer in", "referral_labelAccident/Emergency",
              "prearranged_overnight",
              "admission_periodAfternoon", "admission_periodEvening",
              "admission_periodNight")

nb_coef <- coef(summary(nb_sa4))
nb_irr <- data.frame(
  Variable = rownames(nb_coef),
  IRR      = exp(nb_coef[, "Estimate"]),
  CI_low   = exp(nb_coef[, "Estimate"] - 1.96 * nb_coef[, "Std. Error"]),
  CI_high  = exp(nb_coef[, "Estimate"] + 1.96 * nb_coef[, "Std. Error"]),
  p_value  = nb_coef[, "Pr(>|z|)"],
  row.names = NULL
) %>%
  filter(Variable %in% key_vars) %>%
  mutate(
    Variable = factor(Variable, levels = rev(key_vars)),
    across(c(IRR, CI_low, CI_high, p_value), ~ round(.x, 3))
  )

cat("\n── SA4 NB key explanatory effects: IRR (95% Wald CI) ──\n")
print(nb_irr, row.names = FALSE)
write.csv(nb_irr, "plots/sa4_nb_key_irr.csv", row.names = FALSE)

p_nb_irr <- ggplot(nb_irr, aes(x = IRR, y = Variable)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
  geom_errorbarh(aes(xmin = CI_low, xmax = CI_high), height = 0.18) +
  geom_point(size = 2) +
  scale_x_log10() +
  labs(title = "SA4: Negative Binomial key explanatory effects",
       x = "Incidence rate ratio (log scale)", y = NULL) +
  theme_minimal()
ggsave("plots/p_nb_irr.png", p_nb_irr, width = 8, height = 5)

# SA5: + had_theatre + theatre_min
lmer_sa5 <- lmerTest::lmer(
  log(los) ~ age + sex_label + urgency_label + care_type_label +
    num_diagnoses + insurer_group + prearranged_overnight +
    referral_label + admission_period + had_theatre + theatre_min + (1 | DRG),
  data = df_model, REML = FALSE
)

# ── SA coefficient comparison (exp scale = multiplicative effect on LOS) ──────
extract_exp_coef <- function(model, vars, is_glm = FALSE) {
  cf <- if (is_glm) coef(model) else fixef(model)
  round(exp(cf[vars]), 3)
}

sa_coef <- data.frame(
  Variable    = key_vars,
  Main        = extract_exp_coef(lmer_full, key_vars),
  SA1_ccu     = extract_exp_coef(lmer_sa1,  key_vars),
  SA2_rDRG    = extract_exp_coef(lmer_sa2,  key_vars),
  SA3_nopre   = extract_exp_coef(lmer_sa3,  key_vars),
  SA4_NB      = extract_exp_coef(nb_sa4,    key_vars, is_glm = TRUE),
  SA5_theatre = extract_exp_coef(lmer_sa5,  key_vars)
)

cat("\n── SA coefficient comparison (exp(coef), multiplicative effect on LOS) ──\n")
print(sa_coef, row.names = FALSE)

# ── Forest plot: key model coefficients ───────────────────────────────────────
ci_raw <- confint(lmer_full, parm = "beta_", method = "Wald")

forest_df <- data.frame(
  Variable = names(fixef(lmer_full)),
  estimate = fixef(lmer_full),
  lower    = ci_raw[, 1],
  upper    = ci_raw[, 2]
) %>%
  filter(Variable %in% key_vars) %>%
  mutate(
    exp_est  = exp(estimate),
    exp_low  = exp(lower),
    exp_high = exp(upper),
    label = recode(Variable,
      "age"                              = "Age (per year)",
      "num_diagnoses"                    = "No. Diagnoses (per unit)",
      "urgency_labelElective"            = "Urgency: Elective vs Emergency",
      "urgency_labelNot assigned"        = "Urgency: Not assigned vs Emergency",
      "referral_labelTransfer in"        = "Referral: Transfer in vs GP",
      "referral_labelAccident/Emergency" = "Referral: A&E vs GP",
      "prearranged_overnight"            = "Prearranged overnight",
      "admission_periodAfternoon"        = "Admission: Afternoon vs Morning",
      "admission_periodEvening"          = "Admission: Evening vs Morning",
      "admission_periodNight"            = "Admission: Night vs Morning"
    ),
    label = factor(label, levels = rev(unique(label)))
  )

p_forest <- ggplot(forest_df, aes(x = exp_est, y = label)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
  geom_errorbarh(aes(xmin = exp_low, xmax = exp_high),
                 height = 0.25, colour = "#000F46") +
  geom_point(size = 3, colour = "#000F46") +
  scale_x_log10() +
  labs(title = "Key Factors Associated with LOS",
       x = "Multiplicative effect on LOS (log scale)", y = NULL) +
  theme_minimal(base_size = 12)

ggsave("plots/p_forest.png", p_forest, width = 6, height = 4)
cat("\nForest plot saved to plots/p_forest.png\n")

# ── SA RMSE comparison ────────────────────────────────────────────────────────
sa_rmse <- data.frame(
  Model = c("Main (lmer)", "SA1 +CCU", "SA2 rare DRG",
            "SA3 -prearranged", "SA4 NB", "SA5 +theatre"),
  RMSE  = round(c(
    sqrt(mean((df_model$los - exp(predict(lmer_full)))^2)),
    sqrt(mean((df_model$los - exp(predict(lmer_sa1)))^2)),
    sqrt(mean((df_sa2$los   - exp(predict(lmer_sa2)))^2)),
    sqrt(mean((df_model$los - exp(predict(lmer_sa3)))^2)),
    sqrt(mean((df_model$los - predict(nb_sa4, type = "response"))^2)),
    sqrt(mean((df_model$los - exp(predict(lmer_sa5)))^2))
  ), 3)
)
cat("\n── SA model fit comparison ──\n")
lmer_models <- list(lmer_full, lmer_sa1, lmer_sa2, lmer_sa3, lmer_sa5)
mar_r2  <- sapply(lmer_models, function(m) as.numeric(r2(m)$R2_marginal))
cond_r2 <- sapply(lmer_models, function(m) as.numeric(r2(m)$R2_conditional))

sa_fit <- data.frame(
  Model       = c("Main (lmer)", "SA1 +CCU", "SA2 rare DRG",
                  "SA3 -prearranged", "SA4 NB (no R2)", "SA5 +theatre"),
  AIC         = round(c(AIC(lmer_full), AIC(lmer_sa1), AIC(lmer_sa2),
                        AIC(lmer_sa3), AIC(nb_sa4), AIC(lmer_sa5)), 1),
  Marginal_R2 = round(c(mar_r2[1:4], NA, mar_r2[5]), 3),
  Cond_R2     = round(c(cond_r2[1:4], NA, cond_r2[5]), 3),
  RMSE        = sa_rmse$RMSE
)
print(sa_fit, row.names = FALSE)

# ── INTERACTION EXPLORATION ───────────────────────────────────────────────────
png("plots/p_interactions.png", width = 1400, height = 900, res = 120)
par(mfrow = c(2, 3), mar = c(4, 4, 3, 6))

interaction.plot(df_model$num_diagnoses, df_model$urgency_label, log(df_model$los),
  fun = mean, type = "b", pch = 19, lwd = 1.5,
  main = "Comorbidity × Urgency", xlab = "No. diagnoses",
  ylab = "Mean log(LOS)", trace.label = "Urgency", col = 1:4)

interaction.plot(df_model$age_group, df_model$urgency_label, log(df_model$los),
  fun = mean, type = "b", pch = 19, lwd = 1.5,
  main = "Age × Urgency", xlab = "Age group",
  ylab = "Mean log(LOS)", trace.label = "Urgency", col = 1:4)

interaction.plot(df_model$num_diagnoses, df_model$care_type_label, log(df_model$los),
  fun = mean, type = "b", pch = 19, lwd = 1.5,
  main = "Comorbidity × Care Type", xlab = "No. diagnoses",
  ylab = "Mean log(LOS)", trace.label = "Care", col = 1:7)

interaction.plot(df_model$age_group, df_model$care_type_label, log(df_model$los),
  fun = mean, type = "b", pch = 19, lwd = 1.5,
  main = "Age × Care Type", xlab = "Age group",
  ylab = "Mean log(LOS)", trace.label = "Care", col = 1:7)

interaction.plot(df_model$admission_period, df_model$urgency_label, log(df_model$los),
  fun = mean, type = "b", pch = 19, lwd = 1.5,
  main = "Admission Period × Urgency", xlab = "Admission period",
  ylab = "Mean log(LOS)", trace.label = "Urgency", col = 1:4)

interaction.plot(df_model$referral_label, df_model$urgency_label, log(df_model$los),
  fun = mean, type = "b", pch = 19, lwd = 1.5,
  main = "Referral × Urgency", xlab = "",
  ylab = "Mean log(LOS)", trace.label = "Urgency", col = 1:4,
  xaxt = "n")
axis(1, at = 1:nlevels(df_model$referral_label),
     labels = levels(df_model$referral_label), las = 2, cex.axis = 0.7)

dev.off()
cat("\nInteraction plots saved to plots/p_interactions.png\n")
