# Why Do Some Patients Stay Longer Than Their Diagnosis Explains?

A DRG-adjusted analysis of hospital length of stay (LOS), built on a de-identified Australian Hospital Casemix Protocol (HCP)-style dataset: 6,596 inpatient episodes, one hospital, one year.

**Stack:** R (dplyr, lme4, lmerTest, performance, ggplot2) · log-linear mixed-effects model with a random intercept for DRG

---

## How big is the problem

Length of stay is one of the largest controllable costs in a hospital. Every unexplained extra day is a bed another patient couldn't use, plus added risk for the one occupying it. This hospital's inpatient episodes consume roughly **20,400 bed days a year**.

Not all of that is inefficiency: some patients are genuinely sicker, and DRG (Diagnosis Related Group) is the standard way to account for that. Once you do, **DRG case mix explains about half of the variation in LOS (ICC ≈ 0.50)**, and that half isn't fixable, so it shouldn't be scored as a performance problem. Compare raw LOS across wards or time periods without adjusting for it, and half of what you're seeing is just which patients they happened to treat.

**The question this analysis answers:** once you've adjusted for how sick a patient is, what's still driving how long they stay in the other half, and which parts of *that* can a hospital actually change?

---

## The key findings

Three things in the unexplained half are specific enough to act on. The decision boundary is the "Controllable?" column: only two of the three are levers a hospital can actually pull.

| Driver | Effect (DRG-adjusted) | Controllable? | Scale |
|---|---|---|---|
| Comorbidity burden | +7.4% LOS per additional diagnosis | No, it's case mix | Not a savings target; its value is making benchmarking risk-adjusted |
| Unplanned vs. prearranged pathway | Prearranged episodes run 8.5% shorter | Yes, for patients who could be scheduled in advance | Up to ~880 bed days/year *if* fully realized (upper bound, see Risks) |
| Evening arrival (6–10pm) | +5–6% LOS vs. morning arrivals | Yes, admission-time process | ~125 to 150 bed days/year (~38 to 45 extra episodes' worth of capacity at this hospital's average 3.3-day stay) |

All three are about how the system responds to them, which is exactly what makes the controllable two actionable.

Bed days are the unit used throughout because cost/per-diem data isn't in this dataset. Converting to dollars is a one-line multiplication once you apply your own per-diem rate; converting to capacity, a rough proxy, is bed days divided by the ~3.3-day average LOS.

---

## What to do about it

**1. Fix the evening-admission gap.**
Patients admitted 6–10pm stay 5–6% longer than morning admissions, DRG and urgency held constant; night arrivals (after 10pm) show no such effect, so this isn't just "later is worse." Likely cause: they miss the same-day window for medical review and discharge planning, and that work slides to the next morning.
→ Review the evening admission workflow to confirm where the delay actually sits.
→ If it's confirmed as process rather than clinical necessity, standardise an admission-time checklist that front-loads the review and discharge-planning trigger, instead of waiting for the next day's round.
→ **~589 evening admissions/year, consuming ~2,500 bed days/year.** Even a 5% cut in their LOS frees **~125 bed days/year**; 6% frees **~150**.

**2. Separate risk-adjusted benchmarks for elective vs. emergency admissions.**
Raw LOS comparisons across wards, clinicians, or time periods are currently comparing different patient populations, not different performance: DRG alone explains ~50% of the spread. "Not assigned" urgency patients should be benchmarked against emergency admissions for now (75% of them arrive via A&E or transfer, the same channels), while a coding audit runs on that field in parallel.
→ **Commercial payoff:** fair cost comparisons and outlier flags that survive scrutiny, including in insurer negotiations on per-diem outlier compensation.

**3. Case-review the 7 F41B outliers, not a policy change.**
Within DRG F41B (cardiac rhythm), 7 patients this year stayed far longer than the model expected, and unlike the other outlier-heavy DRGs, they weren't older or more complex than the rest of F41B. That rules out the clinical explanation and points at something process- or case-specific.
→ Seven cases is too small to justify a system-wide fix, but exactly the right size for a targeted clinical review to find out what actually happened, and whether it recurs.

**4. Where the elective pathway has room, it's the biggest lever of the four, on paper.** Episodes booked in advance run meaningfully shorter than otherwise-similar unplanned ones. If a material share of the roughly 4,200 currently-unplanned elective admissions a year could realistically be moved earlier in the pathway, closing even part of that gap is worth up to ~880 bed days/year, several times the evening-admission fix. That "if" is a clinical operations question this dataset can't answer on its own, which is why it's listed last rather than first, and why the number above is a ceiling, not a forecast.

---

## Risks and what's next

What could make these numbers wrong, and what would resolve each one:

- **No ICU data.** ICU episodes are partly absorbed into higher-acuity DRGs via the random intercept, but within a DRG, ICU-vs-not is invisible to this model; read estimates for high-acuity DRGs (e.g. E62A) with that caveat. *Next step: add ICU flag/days if it becomes available.*
- **Single hospital, one-year window.** No cross-site or temporal-stability check yet. *Next step: train on the earlier months, validate on the later ones, and confirm the three effect sizes hold.*
- **The elective-pathway lever (#4) is a hypothesis, not a validated saving.** The 8.5% effect is real and DRG-adjusted, but converting it into "X admissions could realistically move pathway" needs clinical input this dataset doesn't contain. *Next step: a scoping conversation with clinical ops on which currently-unplanned elective admissions could genuinely be scheduled in advance.*
- **"Not assigned" urgency is a coding gap, not a confirmed process fix.** Benchmarking it against emergency admissions is a reasonable interim proxy (75% of it shares emergency's referral pathways), not a permanent answer. *Next step: audit the urgency field directly.*
- **Comorbidity effect modelled as linear**, though EDA showed acceleration above ~7 diagnoses. *Next step: a spline term, worth doing if this ever moves toward individual-level benchmarking rather than population-level effects.*
- **F41B is 7 episodes: a lead, not a finding.** *Next step: the case review itself; if a recurring cause turns up, it becomes a policy recommendation.*

---

## How much to trust the numbers above

**Dataset.** De-identified private-hospital inpatient data, HCP format, June 2022 to June 2023, N = 6,596 overnight episodes after excluding same-day (LOS is administratively ~zero for those, a different pathway rather than a shorter version of the same one). No ICU data; see Risks above.

**DRG really does explain about half the variance (ICC ≈ 0.50).** This is the number that justifies risk-adjusted benchmarking in the first place: compare raw LOS across wards or periods without adjusting for case mix, and half of what you're seeing is just which patients they happened to treat, not performance.

**Model chosen by explicit comparison, not by default.**

| Model | Params | AIC | R² | |
|---|---|---|---|---|
| No DRG adjustment | ~10 | 12,440 | 0.40 | clearly missing something large |
| **DRG as random intercept** | **28** | **9,310** | **0.63** | **chosen: 87% of the AIC gain for 6% of the parameter cost** |
| DRG as fixed effect (dummy per DRG) | 501 | 8,854 | 0.68 | marginal gain, can't handle DRGs with 1–3 patients, overfitting risk |

Outcome modelled as `log(LOS)`. LOS is heavily right-skewed (median 2 days, mean 3.3, max 69), and logging turns coefficients into percentage effects, which is how the findings above are stated.

**Three headline effects held up across every check that could break them:** alternative variable sets, a negative-binomial specification (fixed DRG effects, since some DRGs are too sparse for a random effect), and merging sparse DRGs into an "Other" bucket. Comorbidity count, prearranged pathway, and evening admission stayed significant with similar effect sizes in all five sensitivity analyses. Full detail in [`report/presentation_script.md`](report/presentation_script.md), Q&A section.

**Diagnostics are honest, not just clean.** Residuals behave well for typical cases; the most extreme stays have more error, which is expected given the outcome's skew and acceptable because the model is estimating average effects, not individual predictions.

---

## Repository structure

```
portfolio/
├── README.md                  ← you are here
├── data/
│   ├── hospital_los_dataset.xlsx      # raw HCP-format episode data
│   ├── hcp-data-specifications.xlsx   # public HCP data dictionary
│   └── df_clean.rds                   # cleaned analysis dataset (generated by 01_eda.R)
├── scripts/
│   ├── 01_eda.R                # cleaning, recoding, exploratory analysis
│   └── 02_model.R              # model comparison, final model, sensitivity analyses
├── plots/                      # all generated figures (EDA + model diagnostics)
└── report/
    └── presentation_script.md  # full narrative walkthrough + anticipated Q&A
```

**To reproduce:** open R with working directory set to `portfolio/`, run `scripts/01_eda.R` first (produces `data/df_clean.rds` and the EDA plots), then `scripts/02_model.R` (produces the model comparison, diagnostics, and sensitivity analysis plots).

---

## Why this project

I wanted something that reads like a decision document, not a lab report: the answer up front, the payoff in bed days rather than a coefficient, and the methodology available for anyone who wants to check the work rather than forced on everyone up front. The full modelling walkthrough, every variable I ruled out and why, and anticipated Q&A on each choice, is in [`report/presentation_script.md`](report/presentation_script.md).
