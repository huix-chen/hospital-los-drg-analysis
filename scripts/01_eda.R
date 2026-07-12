# 01_eda.R
# Exploratory analysis of a de-identified Australian HCP-format hospital
# inpatient dataset. Run from the `portfolio/` directory. Produces the
# cleaned modelling dataset (data/df_clean.rds) and all EDA plots in plots/.

# Libraries
options(device = "quartz")
library(readxl)
library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)
library(lubridate)

# Helper: Cramér's V for two categorical variables
cramers_v <- function(x, y) {
  tbl <- table(droplevels(as.factor(x)), droplevels(as.factor(y)))
  chi <- chisq.test(tbl, correct = FALSE)$statistic
  n   <- sum(tbl)
  k   <- min(nrow(tbl), ncol(tbl))
  sqrt(chi / (n * (k - 1)))
}

#  Load data
df <- read_excel("data/hospital_los_dataset.xlsx", na = c("", "NA", "N/A"))
cat("Dimensions:", nrow(df), "rows x", ncol(df), "cols\n")

#  Parse dates (stored as DDMMYYYY integer, leading zero dropped) 
parse_hcp_date <- function(x) {
  s <- formatC(as.integer(x), width = 8, flag = "0")
  as.Date(s, format = "%d%m%Y")
}
df_parsed <- df %>%
  mutate(
    dob           = parse_hcp_date(DateOfBirth),
    admission_dt  = parse_hcp_date(AdmissionDate),
    separation_dt = parse_hcp_date(SeparationDate),
    age           = as.integer(difftime(admission_dt, dob, units = "days") / 365.25),
    los           = as.integer(difftime(separation_dt, admission_dt, units = "days")),
    age_group     = cut(age,
                        breaks = c(0, 17, 34, 49, 64, 79, Inf),
                        labels = c("0-17", "18-34", "35-49", "50-64", "65-79", "80+"),
                        right  = TRUE),
    num_diagnoses = rowSums(!is.na(across(starts_with("AdditionalDiagnosis")))) + 1
  )
View(df_parsed) 
# 很重要
# Age
# Sex
# UrgencyOfAdmission
# CareType
# DRG= PrincipalDiagnosis+ Additional Diag + procedure + age + died + new born + comorbidities
# num_diagnoses
# AdmissionTime
# SameDayStatus
# Readmission28Days（要小心，下面讲）

# 有可能需要 (EDA观察)
# SourceOfReferral
# TransferInProviderNumber
# DischargeIntention # 出院计划是在住院期间决定的，和 LOS 是同步发生的，不是原因
# ModeOfSeparation # 怎么离开的（出院/转院/死亡）是结果，不是预测变量
# TransferOutProviderNumber # 出院时发生的事

# 收费是LOS的结果
#  Recode categoricals
df_recoded <- df_parsed %>%
  mutate(
    sex_label       = factor(Sex, levels = c(1, 2, 3, 9),
                             labels = c("Male", "Female", "Other", "Not stated")),
    urgency_label   = factor(UrgencyOfAdmission, levels = c(1, 2, 3, 9),
                             labels = c("Emergency", "Elective", "Not assigned", "Not unknown")),
    same_day        = factor(SameDayStatus, levels = c(0, 1, 2),
                             labels = c("Same-day arranged", "Same-day", "Overnight")),
    care_type_label = factor(CareType, levels = c(1, 2, 3, 4, 5, 6, 7),
                             labels = c("Acute", "Rehabilitation", "Palliative",
                                        "Geriatric evaluation", "Psychogeriatric",
                                        "Maintenance", "Newborn")),
    referral_label        = factor(SourceOfReferral,
                                   levels = c(0, 1, 2, 4, 7, 8, 9),
                                   labels = c("Born in hospital", "Transfer in",
                                              "Statistical admission", "Accident/Emergency",
                                              "Nursing Home", "Medical Practitioner", "Other")),
    icu_flag              = ICU_Days > 0 & !is.na(ICU_Days),
    ccu_flag              = CCU_Days > 0 & !is.na(CCU_Days),
    prearranged_overnight = as.integer(SameDayStatus == 0),
    admission_hour        = as.integer(AdmissionTime) %/% 100,
    admission_period      = case_when(
      admission_hour >= 6  & admission_hour < 12 ~ "Morning",
      admission_hour >= 12 & admission_hour < 18 ~ "Afternoon",
      admission_hour >= 18 & admission_hour < 22 ~ "Evening",
      TRUE                                        ~ "Night"
    )
  )
View(df_recoded)

#  Working dataset: remove implausible LOS
df_clean <- df_recoded %>% filter(!is.na(los), los >= 0, los <= 365, age >= 0, age <= 110,
                                  same_day %in% c("Overnight", "Same-day arranged"), # nolint
                                  admission_dt >= as.Date("2022-06-01")) %>%
  mutate(insurer_group = ifelse(is.na(InsurerIdentifier), "Uninsured/Other", InsurerIdentifier)) # nolint
nrow(df_recoded) - nrow(df_clean)  # number of rows removed
# 0 ICU days and hours
table(df_clean$ICU_Days, useNA = "always")
table(df_clean$ICU_Hours, useNA = "always")
# 这家医院没有 ICU（私立小医院或日间手术中心很常见）
# ICU 数据没有被记录进这个系统（ICU 可能单独在另一个系统里）
# 数据导出时 ICU 字段被清零了（数据质量问题）


# CCU vs TransferOut correlation
cat("\n── CCU flag distribution ──\n")
print(table(df_clean$ccu_flag, useNA = "always"))

cat("\n── CCU vs LOS ──\n")
df_clean %>%
  group_by(ccu_flag) %>%
  summarise(n = n(),
            mean_los   = round(mean(los), 1),
            median_los = median(los)) %>%
  print()

cat("\n── CCU vs TransferOut cross-tab ──\n")
transfer_out <- !is.na(df_clean$TransferOutProviderNumber)
print(table(ccu = df_clean$ccu_flag, transfer_out = transfer_out))

cat("\n── Cramér's V: CCU vs TransferOut ──\n")
cat(sprintf("V = %.3f\n", cramers_v(df_clean$ccu_flag, transfer_out)))

# CCU 病人里 TransferOut 的比例
cat("\n── TransferOut rate by CCU flag ──\n")
df_clean %>%
  mutate(transfer_out = !is.na(TransferOutProviderNumber)) %>%
  group_by(ccu_flag) %>%
  summarise(n = n(),
            transfer_out_pct = round(mean(transfer_out) * 100, 1)) %>%
  print()

# CCU 病人按 DRG 看 LOS — 验证"CCU=心脏病+短住院"的假设
cat("\n── CCU患者按DRG的LOS（Top 10 by n）──\n")
df_clean %>%
  filter(ccu_flag) %>%
  group_by(DRG) %>%
  summarise(n          = n(),
            mean_los   = round(mean(los), 1),
            median_los = median(los),
            .groups    = "drop") %>%
  arrange(desc(n)) %>%
  slice_head(n = 10) %>%
  print()

cat("\n── Hospital type distribution ──\n")
print(table(df_clean$HospitalType)) # 只有私立医院

# SECTION 1: DATA OVERVIEW

cat("\n── Missing values (key columns) ──\n")
key_cols <- c("age", "los", "Sex", "DRG", "CareType",
              "UrgencyOfAdmission", "SameDayStatus",
              "PrincipalDiagnosis", "num_diagnoses",
              "AdmissionTime", "Readmission28Days",
              "SourceOfReferral", "TransferInProviderNumber")
missing_summary <- df_parsed %>%
  summarise(across(all_of(key_cols), ~ round(mean(is.na(.)) * 100, 1))) %>%
  pivot_longer(everything(), names_to = "column", values_to = "pct_missing")
print(missing_summary)

# Episodes by month
# 比如同一个病人今年做了膝盖手术，3个月后又来做另一侧，这是 2 episodes，1 patient。
p_monthly <- df_clean %>%
  filter(!is.na(admission_dt)) %>%
  mutate(month = floor_date(admission_dt, "month")) %>%
  count(month) %>%
  ggplot(aes(x = month, y = n)) +
  geom_line(colour = "steelblue", linewidth = 0.8) +
  geom_point(colour = "steelblue", size = 2) +
  scale_x_date(date_labels = "%b %Y") +
  labs(title = "Monthly Episode Volume", x = NULL, y = "Episodes") +
  theme_minimal(base_size = 13)
ggsave("plots/p_monthly.png", p_monthly, width = 8, height = 5)


# SECTION 2: PATIENT PROFILE

# Sex distribution  
# 17:13
p_sex <- df_clean %>%
  filter(!is.na(sex_label)) %>%
  count(sex_label) %>%
  ggplot(aes(x = sex_label, y = n, fill = sex_label)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = comma(n)), vjust = -0.4, size = 4) +
  labs(title = "Episodes by Sex", x = NULL, y = "Count") +
  theme_minimal(base_size = 13)
ggsave("plots/p_sex.png", p_sex, width = 8, height = 5)

female_overnight <- df_clean %>%
  filter(sex_label %in% c("Male", "Female")) %>%
  count(sex_label, care_type_label) %>%
  group_by(sex_label) %>%
  mutate(pct = round(n / sum(n) * 100, 1))
print(female_overnight)

# Age distribution, most are from 60-80
p_age <- ggplot(df_clean, aes(x = age)) +
  geom_histogram(binwidth = 5, fill = "steelblue", colour = "white") +
  labs(title = "Patient Age Distribution at Admission", x = "Age (years)", y = "Count") +
  theme_minimal(base_size = 13)
ggsave("plots/p_age.png", p_age, width = 8, height = 5)

# Urgency split, most are elective
 p_urgency <- df_clean %>%
  filter(!is.na(urgency_label), urgency_label %in% c("Emergency", "Elective", "Not assigned")) %>%
  count(urgency_label) %>%
  mutate(pct = n / sum(n)) %>%
  ggplot(aes(x = urgency_label, y = n, fill = urgency_label)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = paste0(comma(n), "\n(", percent(pct, accuracy = 1), ")")),
            vjust = -0.3, size = 3.8) +
  labs(title = "Urgency of Admission", x = NULL, y = "Episodes") +
  theme_minimal(base_size = 13)
ggsave("plots/p_urgency.png", p_urgency, width = 8, height = 5)

# 看每个chapter letter里最常见的DRG和它们的临床含义
df_clean %>%
  mutate(chapter = substr(DRG, 1, 1),
         partition = substr(DRG, 4, 4)) %>%
  group_by(chapter) %>%
  summarise(
    n = n(),
    top_drg = names(sort(table(DRG), decreasing = TRUE))[1],
    mean_los = round(mean(los, na.rm = TRUE), 1)
  ) %>%
  arrange(desc(n))

# PrincipalDiagnosis and Procedure1 vs DRG
cat("\n── Unique PrincipalDiagnosis per DRG (should be low if collinear) ──\n")
drg_diag_overlap <- df_clean %>%
  group_by(DRG) %>%
  summarise(unique_diag = n_distinct(PrincipalDiagnosis), n = n()) %>%
  filter(n >= 50) %>%
  arrange(desc(unique_diag))
print(drg_diag_overlap)

# Additional variables check
# Medical Practitioner（8）：4485人，占绝大多数——私立医院典型，由私人医生转介
# Accident/Emergency（4）：1025人
# Transfer in（1）：755人——这组 LOS 可能最长，值得重点看

cat("\n── SourceOfReferral distribution ──\n")
print(table(df_clean$referral_label, useNA = "always"))

cat("\n── SourceOfReferral vs LOS ──\n")
# referral_label 是个有用的预测变量—
# Transfer in 和 Accident/Emergency 的 LOS 明显高于 Medical Practitioner。值得放进模型
df_clean %>%
  filter(!is.na(referral_label)) %>%
  group_by(referral_label) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los)) %>%
  arrange(desc(mean_los)) %>%
  print()

cat("\n── TransferIn patients vs LOS ──\n")
df_clean %>%
  mutate(transfer_in = !is.na(TransferInProviderNumber)) %>%
  group_by(transfer_in) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los)) %>%
  print()

# 两个定义的差距来源：A&E病人里有大量从其他医院转来的
# 有TransferInProviderNumber但referral不是"Transfer in"的病人
cat("\n── 有TransferInProviderNumber但referral != Transfer in ──\n")
print(table(
  df_clean$referral_label[
    !is.na(df_clean$TransferInProviderNumber) &
      df_clean$referral_label != "Transfer in"
  ],
  useNA = "always"
))
# A&E转来(mean 4.8天) 和 正式Transfer in(mean 5.3天) LOS相近，
# 都远高于Medical Practitioner(mean 2.5天)
# 所以模型用!is.na(TransferInProviderNumber)更完整
cat("\n── LOS: A&E vs Transfer in vs Medical Practitioner ──\n")
df_clean %>%
  filter(referral_label %in%
    c("Accident/Emergency", "Transfer in", "Medical Practitioner")) %>%
  group_by(referral_label) %>%
  summarise(n = n(), mean_los = round(mean(los), 1),
            median_los = median(los)) %>%
  arrange(desc(mean_los)) %>%
  print()

#晚上入院的病人 LOS 比早上入院的高将近一倍，这是一个医院可以采取措施的运营因素：
#比如改善夜间急诊分流效率、提前安排第二天早上的手术时间表，可以减少这批病人的"等待天数"。
cat("\n── Admission Period vs LOS ──\n")
df_clean %>%
  filter(!is.na(admission_period)) %>%
  group_by(admission_period) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los)) %>%
  arrange(desc(mean_los)) %>%
  print()

# SECTION 3: LOS OVERVIEW

cat("\n── LOS summary by Same-day Status ──\n")
same_day_status <- df_clean %>%
  filter(!is.na(same_day)) %>%
  group_by(same_day) %>%
  summarise(n      = n(),
            min = min(los),
            mean   = round(mean(los), 1),
            median = median(los),
            p75    = quantile(los, .75),
            max    = max(los)) %>%
  print()

same_day_arranged <- df_clean |>
  filter(same_day == "Same-day arranged") |>
  count(los) |>
  mutate(percent = n / sum(n))
print(same_day_arranged)

summary(df_clean$los[df_clean$same_day == "Overnight"])
# LOS distribution (cap at 30 for readability)
p_los_dist <- ggplot(df_clean, aes(x = "", y = los)) +
  geom_boxplot(fill = "#D0D9F0", colour = "#000F46", linewidth = 0.8,
               outlier.colour = "#000F46", outlier.alpha = 0.4, outlier.size = 1.2) +
  labs(title = "Length of Stay (days)", x = NULL, y = NULL) +
  theme_minimal()
ggsave("plots/p_los_dist.png", p_los_dist, width = 3, height = 6)

# DRG median LOS range — motivate (1|DRG) random effect
drg_los_range <- df_clean %>%
  group_by(DRG) %>%
  summarise(median_los = median(los), n = n()) %>%
  filter(n >= 10)
cat(sprintf("\nDRG median LOS: min = %.1f, max = %.1f, across %d DRGs (≥10 episodes)\n",
            min(drg_los_range$median_los),
            max(drg_los_range$median_los),
            nrow(drg_los_range)))

p_drg_spread <- ggplot(drg_los_range, aes(x = median_los)) +
  geom_histogram(binwidth = 1, fill = "#000F46", colour = "white") +
  labs(title = "Distribution of DRG-Specific Median LOS", x = NULL, Y= NULL) +
  theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank())
ggsave("plots/p_drg_spread.png", p_drg_spread, width = 6, height = 3)

# Outliers: proportion with LOS > 14 days
outlier_pct <- mean(df_clean$los > 14 & df_clean$same_day == "Overnight") * 100
cat(sprintf("\nOvernight episodes with LOS > 14 days: %.1f%%\n", outlier_pct))

# SECTION 4: WHAT DRIVES LOS?

#  4a. Top DRGs by mean LOS (min 50 episodes for reliability) 
# E62A的mean和median差很多，所以肯定有outliers
# 想要降低LOS，可以直接看排名高的DRG
top_drg_los <- df_clean %>%
  group_by(DRG) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los)) %>%
  filter(n >= 50) %>%
  arrange(desc(mean_los)) %>%
  slice_head(n = 5)

cat("\n── Top 5 DRGs by mean LOS (min 50 episodes) ──\n")
print(top_drg_los)

p_drg_los <- ggplot(top_drg_los, aes(x = reorder(DRG, mean_los))) +
  geom_col(aes(y = mean_los, fill = "Mean"), alpha = 0.7) +
  geom_point(aes(y = median_los, colour = "Median"), size = 3) +
  scale_fill_manual(values = c("Mean" = "steelblue"), name = NULL) +
  scale_colour_manual(values = c("Median" = "firebrick"), name = NULL) +
  scale_y_continuous(breaks = seq(0, 20, by = 1), minor_breaks = NULL) +
  coord_flip() +
  labs(title = "Top 5 DRGs by Mean and Median LOS (≥50 episodes)",
       x = "DRG", y = "LOS (days)") +
  theme_minimal(base_size = 12) +
  theme(panel.grid.major.y = element_blank(), panel.grid.minor.y = element_blank())
ggsave("plots/p_drg_los.png", p_drg_los, width = 6, height = 4)

# 4b. LOS by Care Type 
# 解释 LOS 差异：给利益相关方说明"LOS 高是因为 Palliative 病人多，不是效率问题"
# 控制变量：做回归时要放进去，不然会混淆其他变量的效果
care_los <- df_clean %>%
  filter(!is.na(care_type_label)) %>%
  group_by(care_type_label) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los)) %>%
  arrange(desc(mean_los))

cat("\n── LOS by Care Type ──\n")
print(care_los)

p_care_los <- ggplot(df_clean %>% filter(!is.na(care_type_label)),
                     aes(x = reorder(care_type_label, los, FUN = median),
                         y = los, fill = care_type_label)) +
  geom_boxplot(outlier.alpha = 0.15, show.legend = FALSE) +
  coord_flip() +
  labs(title = "LOS by Care Type", x = NULL, y = NULL) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor.y = element_blank())
ggsave("plots/p_care_los.png", p_care_los, width = 6, height = 3)

# 4c. LOS by Age Group 
# 18-34 的LOS高一点 是由于产科
age_los <- df_clean %>%
  filter(!is.na(age_group)) %>%
  group_by(age_group) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los))

cat("\n── LOS by Age Group ──\n")
print(age_los)

p_age_los <- ggplot(age_los, aes(x = age_group, y = mean_los, fill = age_group)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = mean_los), vjust = -0.4, size = 4) +
  labs(title = "Mean LOS by Age Group", x = "Age Group", y = "Mean LOS (days)") +
  theme_minimal(base_size = 13)
ggsave("plots/p_age_los.png", p_age_los, width = 8, height = 5)

check_drg <- df_clean %>%
  filter(age_group %in% c("18-34", "35-49")) %>%
  count(age_group, DRG) %>%
  group_by(age_group) %>%
  mutate(pct = round(n/sum(n)*100, 1)) %>%
  arrange(age_group, desc(n)) %>%
  slice_head(n = 5)

# 4e. Emergency vs Elective LOS 
# Not assigned 这批病人实际上行为上更像急诊病人——可能是紧急入院但没有被正式记录为 Emergency
urgency_los <- df_clean %>%
  filter(urgency_label %in% c("Emergency", "Elective", "Not assigned")) %>%
  group_by(urgency_label) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los))

cat("\n── LOS: Emergency vs Elective vs Not assigned ──\n")
print(urgency_los)

p_urgency_los <- ggplot(df_clean %>%
                          filter(urgency_label %in% c("Emergency", "Elective", "Not assigned"), los <= 30),
                        aes(x = urgency_label, y = los, fill = urgency_label)) +
  geom_boxplot(outlier.alpha = 0.15, show.legend = FALSE) +
  labs(title = "LOS by Urgency of Admission", x = NULL, y = NULL) +
  theme_minimal(base_size = 13) +
  theme()
ggsave("plots/p_urgency_los.png", p_urgency_los, width = 6, height = 4)

#  4g. Comorbidity burden vs LOS
comorbidity_los <- df_clean %>%
  mutate(diag_group = cut(num_diagnoses, breaks = c(0, 1, 3, 6, 10, Inf),
                          labels = c("1", "2-3", "4-6", "7-10", "11+"))) %>%
  filter(!is.na(diag_group)) %>%
  group_by(diag_group) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los))

cat("\n── LOS by Number of Diagnoses (comorbidity proxy) ──\n")
print(comorbidity_los)

p_comorbidity <- ggplot(comorbidity_los, aes(x = diag_group, y = median_los, group = 1)) +
  geom_line(colour = "steelblue", linewidth = 1) +
  geom_point(colour = "steelblue", size = 3) +
  geom_text(aes(label = median_los), vjust = -0.8, size = 4) +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.15))) +
  labs(title = "Median LOS by Number of Diagnoses", x = NULL, y = NULL) +
  theme_minimal(base_size = 13) +
  theme(panel.grid.minor.x = element_blank())
ggsave("plots/p_comorbidity.png", p_comorbidity, width = 6, height = 4)

# 4h. LOS by Insurer
# 如果某个 insurer 对应的 LOS 特别长，可能说明那个 insurer 的合同需要重新谈
cat("\n── InsurerIdentifier missing check ──\n")
cat(sprintf("Missing InsurerIdentifier: %d (%.1f%%)\n",
            sum(is.na(df_clean$InsurerIdentifier)),
            mean(is.na(df_clean$InsurerIdentifier)) * 100))
# Missing可能是： 自费病人/工伤保险

missing_insurer <- df_clean %>%
  mutate(insurer_missing = is.na(InsurerIdentifier)) %>%
  group_by(insurer_missing) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los))
print(missing_insurer)

insurer_los <- df_clean %>%
  group_by(InsurerIdentifier) %>%
  summarise(n = n(), mean_los = round(mean(los), 1), median_los = median(los)) %>%
  arrange(desc(mean_los))

cat("\n── LOS by Insurer ──\n")
print(insurer_los)

p_insurer_los <- ggplot(insurer_los,
                        aes(x = reorder(InsurerIdentifier, mean_los), y = mean_los)) +
  geom_col(fill = "mediumpurple") +
  geom_text(aes(label = mean_los), hjust = -0.2, size = 3.5) +
  coord_flip() +
  labs(title = "Mean LOS by Insurer", x = "Insurer", y = "Mean LOS (days)") +
  theme_minimal(base_size = 12)
ggsave("plots/p_insurer_los.png", p_insurer_los, width = 8, height = 5)

# SECTION 5: OUTLIER ANALYSIS (sets up model motivation)

# LOS outliers by DRG: episodes with LOS > 2x the DRG median
# 每个 DRG 里，有多少比例的病人 LOS 超过该 DRG 自己中位数的2倍

drg_medians <- df_clean %>%
  group_by(DRG) %>%
  summarise(drg_median_los = median(los), drg_n = n())

df_combined <- df_clean %>%
  #select(-any_of(c("drg_median_los", "drg_n", "excess_los", "is_outlier"))) %>%
  left_join(drg_medians, by = "DRG") %>%
  mutate(excess_los = los - drg_median_los,
         is_outlier  = los > 2 * drg_median_los & drg_median_los > 0)

cat("\n── LOS outliers (LOS > 2x DRG median) ──\n")
cat(sprintf("Outlier episodes: %d (%.1f%%)\n",
            sum(df_combined$is_outlier, na.rm = TRUE),
            mean(df_combined$is_outlier, na.rm = TRUE) * 100))
# Using a threshold of LOS > 2× the DRG-specific median,
# 379 episodes (5.7%) were classified as outliers
# above the typical private hospital benchmark of <3%


# Geometric mean + 2SD threshold per DRG (log scale)
drg_log_stats <- df_clean %>%
  filter(los > 0) %>%
  group_by(DRG) %>%
  summarise(
    drg_n      = n(),
    trim_point = exp(mean(log(los)) + 2 * sd(log(los))),
    .groups    = "drop"
  )

df_gm <- df_clean %>%
  filter(los > 0) %>%
  left_join(drg_log_stats, by = "DRG") %>%
  mutate(is_outlier_gm = los > trim_point)

cat(sprintf("Geomean+2SD outliers: %d (%.1f%%)\n",
            sum(df_gm$is_outlier_gm, na.rm = TRUE),
            mean(df_gm$is_outlier_gm, na.rm = TRUE) * 100))

outlier_profile_gm <- df_gm %>%
  filter(DRG %in% c("E62A", "I13B", "F41B")) %>%
  group_by(DRG, is_outlier_gm) %>%
  summarise(
    n         = n(),
    mean_age  = round(mean(age), 1),
    mean_diag = round(mean(num_diagnoses), 1),
    .groups   = "drop"
  ) %>%
  arrange(DRG, is_outlier_gm)

print(outlier_profile_gm)



# Top DRGs by outlier rate (min 50 episodes)
outlier_by_drg <- df_combined %>%
  group_by(DRG) %>%
  summarise(n = n(), outlier_rate = round(mean(is_outlier, na.rm = TRUE) * 100, 1)) %>%
  filter(n >= 50) %>%
  arrange(desc(outlier_rate)) %>%
  slice_head(n = 10)

cat("\n── DRGs with highest outlier rates (≥50 episodes) ──\n")
print(outlier_by_drg)

# 看 F76A 的 outlier 和 non-outlier 病人有什么不同
# 如果发现 outlier 的病人更老、诊断更多、或者急诊比例更高，医院就知道：
# 不是效率问题，是病人病情更复杂
# 可以用来和保险公司谈判，争取更高的 outlier 补偿
#"我们 F76A 的 outlier 病人平均年龄76.5岁，诊断数7.8个，
#比普通病人复杂得多，这是客观病情导致的长住院，不是我们效率差。
#请你们为超出部分额外付 per diem（每日补贴）。"
outlier_profile <- df_combined %>%
  filter(DRG %in% outlier_by_drg$DRG) %>%
  group_by(DRG, is_outlier) %>%
  summarise(n             = n(),
            mean_age      = round(mean(age), 1),
            mean_diag     = round(mean(num_diagnoses), 1),
            emergency_pct = round(mean(urgency_label == "Emergency") * 100, 1),
            .groups = "drop") %>%
  arrange(DRG, is_outlier)

cat("\n── Outlier vs Non-outlier profile by DRG ──\n")
print(outlier_profile, n = Inf)

# SECTION 6: COLLINEARITY CHECK (before modelling)

# Continuous: age vs num_diagnoses
cat("\n── Pearson correlation: age vs num_diagnoses ──\n")
cat(sprintf("r = %.3f\n", cor(df_combined$age, df_combined$num_diagnoses, use = "complete.obs")))

cat("\n── Cramér's V (0=no association, 1=perfect) ──\n")
cat(sprintf("care_type vs urgency:    V = %.3f\n", cramers_v(df_combined$care_type_label, df_combined$urgency_label)))
# high corr between referral and urgency 0.541
cat(sprintf("referral  vs urgency:    V = %.3f\n", cramers_v(df_combined$referral_label,  df_combined$urgency_label)))
# high corr between referral and transfer in privider 1
cat(sprintf("referral  vs transfer_in: V = %.3f\n", cramers_v(df_combined$referral_label,
                                                               !is.na(df_combined$TransferInProviderNumber))))

# MDC vs care_type 0.622
df_combined <- df_combined %>% mutate(MDC = substr(DRG, 1, 1))
cat(sprintf("MDC       vs care_type:  V = %.3f\n", cramers_v(df_combined$MDC, df_combined$care_type_label)))

# ── PPT EDA combined plots ─────────────────────────────────────────────────────
library(patchwork)

p_referral_los <- df_clean %>%
  filter(referral_label %in% c("Transfer in", "Accident/Emergency", "Medical Practitioner")) %>%
  mutate(referral_label = factor(referral_label,
    levels = c("Transfer in", "Accident/Emergency", "Medical Practitioner"))) %>%
  ggplot(aes(x = referral_label, y = los)) +
  geom_boxplot(fill = "steelblue", outlier.alpha = 0.15) +
  coord_cartesian(ylim = c(0, 25)) +
  labs(title = "Referral Source vs LOS", x = NULL, y = "LOS (days)") +
  theme_minimal(base_size = 13)

p_period_los <- df_clean %>%
  filter(!is.na(admission_period)) %>%
  mutate(admission_period = factor(admission_period,
    levels = c("Morning", "Afternoon", "Evening", "Night"))) %>%
  ggplot(aes(x = admission_period, y = los)) +
  geom_boxplot(fill = "steelblue", outlier.alpha = 0.15) +
  coord_cartesian(ylim = c(0, 25)) +
  labs(title = "Admission Period vs LOS", x = NULL, y = "LOS (days)") +
  theme_minimal(base_size = 13)

ggsave("plots/p_referral_los.png", p_referral_los , width = 6, height = 3)
ggsave("plots/p_period_los.png", p_period_los , width = 6, height = 3)
# Save cleaned dataset for modelling
saveRDS(df_clean, "data/df_clean.rds")
cat("\ndf_clean saved to data/df_clean.rds\n")
cat("\nEDA complete.\n")

# E62A	outlier 年龄 88.2 vs 73.2，诊断数 14.1 vs 8.2，差距最大
# I03B	outlier 年龄 82.2 vs 69，诊断数 9.5 vs 3.8
# I13B	outlier 年龄 60.3 vs 43.3，年轻病人住这么久说明病情特别复杂
# J06A	诊断数 8.9 vs 4.1，翻倍
# 唯一例外是 F41B：outlier 组反而更年轻（64.9 vs 68.6），诊断数也只是稍高。这个值得单独看——可能不是病情复杂，而是真的有流程问题。

