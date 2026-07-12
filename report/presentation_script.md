# Presentation Script: Hospital Length of Stay Analysis
**Huixin Chen | Personal Data Science Project | ~15 minutes**

---

## HOW TO USE THIS DOCUMENT

Each slide has:
- **Evaluator requirement met**: maps to the brief so you know you're covering it
- **Talking points**: bullet reminders of what to hit
- **Full script**: word for word, adjust to your natural voice
- **Time target**: keep yourself on track

---

## SLIDE 1: TITLE
**[Time: ~30 seconds]**
**Requirement met:** Sets up the model subject; signals structure

**Talking points:**
- Why it matters: LOS drives cost and resource use, this is the hook, not background noise
- Why THIS variable: EDA showed it's highly variable, and case mix doesn't fully explain that variation
- The logical leap: if variation is large and case mix can't account for all of it, something else is hiding in the leftover variation, and it's findable
- That hidden "something else" is exactly what the model is built to dig out, this is the through-line for the whole talk

**Full script:**
> "Thanks. Here's the question I wanted to answer. We use a patient's Diagnosis Related Group, or DRG, to capture how sick they are. So beyond that, what else affects how long they stay in hospital?
>
> Length of stay is one of the biggest cost drivers in a hospital. I picked it because the EDA showed two things early on. First, length of stay varied a lot. Second, DRG only explained part of that. So something else must be driving the rest, and that's what I built this model to find."

---

## SLIDE 2: BUSINESS QUESTION & HYPOTHESIS
**[Time: ~1 minute]**
**Requirement met:** Hypothesis; commercial and operational framing

**Talking points:**
- Frame why LOS matters commercially and operationally *before* diving into analysis
- State the hypothesis explicitly, the panel needs to hear this word
- Name the analytical approach

**Full script:**
> "Length of stay drives bed occupancy, staffing costs, and care quality. And an extra day we can't explain costs money, and adds risk for the patient. But not all of that is inefficiency. Some patients are just sicker than others, so we need to account for that first. That's what DRGs are for.
>
> My **hypothesis** was this. Even after we adjust for DRG, patient factors like age and how many conditions someone has, plus operational things like admission timing and pathway, still independently affect length of stay.
>
> If that's true, it gives us something we can actually act on. Not something about who the patient is, but something about how the system responds to them.
>
> I used a linear mixed effects model, I'll walk through that shortly. The goal was an explanatory model. Something that tells us which factors matter and by how much, not a black box that just produces predictions."

---

## SLIDE 3: DATASET OVERVIEW
**[Time: ~45 seconds]**
**Requirement met:** Dataset overview and significance

**Talking points:**
- Name the dataset type and scope
- Explicitly call out *why the dataset is significant*, it's in the brief
- Note the key limitation (no ICU data) upfront, shows rigour

**Full script:**
> "The dataset is private hospital inpatient data, in HCP format, covering 2022 to 2023. That's 6,596 overnight episodes. I excluded same-day admissions right away, because their length of stay is zero by definition, they're a completely different kind of pathway.
>
> What makes this dataset useful is that it has several different kinds of information together: patient demographics, clinical details including DRG, admission and referral information, and insurer data. So we can separate clinical complexity from operational factors, and that's exactly the distinction we need to make this analysis useful.
>
> One limitation to flag upfront: there's no ICU information in this dataset. I'll come back to that later."

---

## SLIDE 4: VARIABLE SELECTION
**[Time: ~1 minute]**
**Requirement met:** Methodology, principled variable selection

**Talking points:**
- Frame this as a methodology decision, not a list
- Three criteria: clinical relevance, EDA findings, collinearity
- Exclusions are deliberate, show you thought about data leakage and redundancy

**Full script:**
> "I picked variables based on three things: does it make clinical sense, does the EDA show a pattern, and does it overlap with something I already have. I didn't want two variables measuring basically the same thing.
>
> The full list is on the slide, so I won't read all ten out loud. Roughly, it splits into two groups. Patient-level things, like age, sex, diagnosis count, DRG. And operational things, like care type, urgency, referral source, admission timing, insurer.
>
> What I left out matters just as much. Principal diagnosis, I dropped, because it overlaps too much with DRG, using both would just double count the same information. Transfer provider, I dropped, because it duplicates referral source. Discharge variables, I dropped, because they happen after the admission ends, so using them would be data leakage.
>
> CCU status, I tested separately, in a sensitivity analysis. It's very specific to certain DRGs, so putting it in the main model would mostly just overlap with what DRG already tells us."

---

## SLIDE 5: LOS DISTRIBUTION
**[Time: ~1 minute]**
**Requirement met:** Notable trends; methodology (outcome transformation)

**Talking points:**
- Median 2 days, mean 3.3, max 69: right skewed, this is expected and important
- Log transformation: explain the *why*, not just the *what*
- Outlier definition: principled and DRG relative, not arbitrary

**Full script:**
> "Before I built anything, I looked closely at the outcome itself. Length of stay has a median of 2 days, a mean of 3.3, and a max of 69. That gap between mean and median is a classic sign of skew. A small number of very long stays are pulling the average up.
>
> This matters for the model. So I log transformed length of stay before running the regression. It makes the statistics behave properly. And more usefully, it means the coefficients come out as percentage changes, not a flat number of days. That's a much more natural way to talk about this with clinicians.
>
> I also set a clear rule for outliers. Any episode where length of stay was more than twice the DRG's median counts as an outlier. That gave me 379 episodes, about 5.7% of the data, and I looked at those separately."

---

## SLIDE 6: EDA: WHAT DRIVES LONGER STAYS?
**[Time: ~1 minute]**
**Requirement met:** Notable trends and patterns

**Talking points:**
- Two headline EDA findings that directly motivated model design
- "Not Assigned" *urgency* (not referral source) behaves like emergency: looks like a coding gap in the urgency field specifically
- Number of diagnoses: sharp acceleration above 7, non-linear in the raw data, but linear term adequate in model

**Full script:**
> "Two patterns from the EDA stood out to me.
>
> First, take patients whose urgency of admission is coded Not Assigned, that's a different field from where they were referred from. Their length of stay looks a lot like emergency admissions. And when I checked their referral source, which was fully recorded, about 75% of them came through A&E or a transfer, the same way normal emergency patients come in. So it looks like someone just didn't fill in the urgency field for these patients, it's not really its own category. And that matters, because it changes how we should benchmark them.
>
> Second, the relationship between number of diagnoses and length of stay isn't a straight line. It stays fairly flat at low counts, then climbs fast once you pass seven diagnoses, up to a median of 8 days at 11 or more. That told me it should go into the model as a continuous variable."

---

## SLIDE 7: EDA: CLINICAL PATHWAY AND CASE MIX
**[Time: ~1 minute]**
**Requirement met:** Notable trends; justification for model structure

**Talking points:**
- Care type creates clinically distinct LOS groups, must be controlled for
- DRG E62A mean vs median gap: identifies a high complexity tail worth watching
- Wide DRG level variation directly motivates using DRG as a random grouping variable

**Full script:**
> "Looking at clinical pathways, care type turned out to matter a lot. Palliative episodes have a median stay of 7 days, Newborn 4 days, and Acute patients just 2 days. These are completely different clinical journeys, so care type has to be in the model, otherwise it would distort everything else.
>
> Within DRGs, E62A stood out. The mean length of stay was 9.5 days, but the median was only 7. That gap tells us there's a small group of patients in this DRG staying much longer than the rest. Worth flagging for clinical review."

---

## SLIDE 8: EDA: OUTLIER ANALYSIS
**[Time: ~1 minute]**
**Requirement met:** Notable trends; connecting EDA to recommendations

**Talking points:**
- Compare outliers to non-outliers within each DRG by age and diagnosis count
- E62A, I13B: older, more diagnoses, clinically expected outliers
- F41B: younger, similar diagnosis count, potential process issue, not clinical complexity
- This distinction is what drives Recommendation 3

**Full script:**
> "And zooming out, median length of stay varies a lot across DRGs, some are naturally much longer than others. That's really why I treat DRG differently from the other variables.
>
> Here's the problem: some DRGs only have two or three patients in this data. If I gave each one its own separate number, those small groups would be way too unstable, just two or three patients deciding the whole estimate. So instead, I group patients by DRG. That way, small DRGs borrow strength from the overall pattern instead of swinging wildly, while big DRGs, with hundreds of patients, have enough data that the model basically lets them speak for themselves, so the estimate stays stable. It's just a safer way to handle it.
>
> I took the 379 flagged outlier episodes and asked a simple question. Does their clinical complexity explain the extra time, or is something else going on?
>
> For E62A, that's respiratory failure, and for I13B, the outlier patients were noticeably older, with more diagnoses. So longer stays there are clinically expected, no operational concern.
>
> But F41B, a cardiac rhythm DRG, told a different story. Outlier patients there were younger than the non-outliers, with a similar diagnosis count. That's not a clinical signal, that's a process signal. Seven episodes in F41B stayed far longer than the model expected, and those are the ones most likely to be fixable.
>
> So that's what the EDA told us. It backs up the variables I picked earlier, and it tells us exactly what the model needs to capture. Now let's look at how I actually built it."

---

## SLIDE 9: MODELLING STRATEGY
**[Time: ~1.5 minutes]**
**Requirement met:** Methodology, model selection and justification; testing (model comparison)

**Talking points:**
- Three models were formally compared, this is the *testing* stage
- Frame the comparison in terms the panel will recognise: parsimony vs fit
- Mixed effects: 28 params, AIC 9,310, R² 0.63 vs full DRG fixed: 501 params, AIC 8,854, R² 0.68
- The mixed effects model recovers ~87% of the explanatory gain (AIC basis) at ~6% of the parameter cost

**Full script:**
> "Before I settled on a final model, I tested three different versions to find the right structure.
>
> A baseline model, with no DRG adjustment at all, only explained 40% of the differences in length of stay. So it was clearly missing something big. A full model, where every single DRG gets its own coefficient, got up to an R squared of 0.68. But that cost 501 parameters. With that many parameters, the model gets hard to interpret, and it's prone to overfitting.
>
> The mixed effects model, where DRG is a random intercept instead, gets an R squared of 0.63, using just 28 parameters. The AIC drops from 12,440 with no DRG, to 9,310 for the mixed model, compared to 8,854 for the full model. So with just a small fraction of the parameters, we keep almost all of the explanatory power.
>
> The random intercept is also the right choice conceptually. DRG is a grouping variable. We want to account for how much it varies, not estimate a separate number for every single DRG. That keeps the fixed effects, the things we care about, clean and easy to estimate.
>
> The final model includes age, sex, urgency of admission, care type, number of diagnoses, insurer, referral source, admission period, and overnight patient type."

---

## SLIDE 10: DRG CASE MIX ACCOUNTS FOR HALF OF LOS VARIATION
**[Time: ~1 minute]**
**Requirement met:** Model performance, ICC interpretation; commercial significance

**Talking points:**
- ICC ~0.50: half of all LOS variation is between DRGs, not within them
- This validates the need for DRG adjustment, without it, benchmarks are misleading
- The remaining 50% is where operational fixes live

**Full script:**
> "One of the most important numbers from this model is the ICC, that's short for Intraclass Correlation Coefficient. It just tells us how much of the difference in length of stay comes from which DRG a patient is in, versus everything else.
>
> Here, the ICC is about 0.50. So just knowing a patient's DRG already explains half of the differences in length of stay, on its own. That's a striking number.
>
> In plain terms, if you compare length of stay across wards or time periods without adjusting for DRG first, half of what you're seeing isn't really about performance. It's just because those groups happen to treat different kinds of patients. So that comparison isn't fair, and you can't trust it.
>
> But the other half matters just as much. That's the part that happens within DRGs, driven by things like age, urgency, admission timing, care pathway. And that's exactly the part our fixed effects are measuring."

---

## SLIDE 11: MODEL DIAGNOSTICS
**[Time: ~45 seconds]**
**Requirement met:** Model performance, diagnostic assessment

**Talking points:**
- Be honest about limitations, shows statistical maturity
- Residual tails are heavier than ideal, but central behaviour is good
- Fitness for purpose: explanatory model, not something built to predict individual stays

**Full script:**
> "I ran four checks on this model, to see if it's behaving the way a good model should. There are a couple of things here worth being honest about. For the most extreme cases, the very longest stays, the model has more error. The log transform helps a lot, but it can't completely smooth out how skewed length of stay naturally is.
>
> That said, for most patients, the typical cases, the model fits well. It's doing what we need it to do.
>
> And I want to be clear about what that is. This is an *explanatory* model. We're estimating the direction and size of effects, to understand what drives length of stay. We're not trying to predict any one patient's exact stay. For that goal, this level of accuracy is enough."

---

## SLIDE 12: ROBUSTNESS CHECKS
**[Time: ~45 seconds]**
**Requirement met:** Model testing, sensitivity and robustness

**Talking points:**
- Robustness checks are part of the analytical rigour, name them explicitly
- Alternative variable sets; negative binomial model as an alternative specification
- Core findings stable across all specifications

**Full script:**
> "To check whether the findings hold up, I ran a series of robustness checks. I changed the variable sets and re-ran the model. I also tried a negative binomial model, which fits count data more naturally, as an alternative to the log-linear approach. That model used fixed DRG effects instead of random, because some DRGs are too small for a random effect to work well there.
>
> The main result is, the core findings held up across every version. The three key predictors, diagnosis count, overnight patient type, and admission period, stayed significant with similar effect sizes every time."

---

## SLIDE 13: KEY FINDINGS
**[Time: ~2 minutes]**
**Requirement met:** Notable trends; model output; resource and operational implications

**Talking points:**
- Three headline findings, say the number clearly each time
- Diagnoses: 7.4% per additional diagnosis (patient complexity)
- Prearranged admissions: 8.5% shorter (elective pathway efficiency)
- Afternoon/evening admission: 5 to 6% longer; night: no effect (operational timing)
- Be ready to explain *why* night admissions don't have the same effect

**Full script:**
> "Here are the three findings that survived DRG adjustment, and held up across every robustness check.
>
> **First, patient complexity.** Each additional diagnosis is linked to a 7.4% longer stay, independent of everything else. It's a steady signal, more health conditions, longer stay. That means we can benchmark on a fairer basis, comparing risk-adjusted length of stay across units, clinicians, or time periods, instead of just the raw numbers.
>
> **Second, planning the pathway.** Prearranged overnight admissions are 8.5% shorter than standard ones, even after adjusting for DRG and urgency. This isn't about who the patient is, it's about whether the pathway was planned in advance. So wherever it makes clinical sense, doing more of these prearranged admissions is something that could genuinely help, operationally.
>
> **Third, admission timing.** Patients admitted between 6pm and 10pm stay 5 to 6% longer than morning admissions. But night admissions, after 10pm, show *no* extra effect once DRG is accounted for. So the pressure point is that evening window. These patients arrive too late for same-day medical review and discharge planning, so that work just slides to the next day.
>
> Sex wasn't a significant predictor once we adjusted for case mix. Insurer stayed in as a control variable, but it's probably standing in for socioeconomic factors we didn't measure, not a real causal effect."

---

## SLIDE 14: DATA-DRIVEN RECOMMENDATIONS
**[Time: ~1.5 minutes]**
**Requirement met:** Data-driven recommendations; commercial, care, and operational outcomes

**Talking points:**
- Three recommendations, each explicitly linked to a finding
- Frame each in terms the brief uses: commercial outcomes, patient care, operational efficiency
- Be specific, not "improve processes" but "admission checklist for 6pm to 10pm arrivals"

**Full script:**
> "So this gives us three concrete recommendations, all grounded in the evidence.
>
> **One, separate the benchmarks for elective and emergency admissions, and adjust both for risk.** Combining them just gives misleading comparisons. For the Not Assigned patients, I'd benchmark them against emergency patients for now, since that's where most of them came from, while a coding review happens in parallel. This gives fairer, more useful performance monitoring. *Commercial impact: fairer cost comparisons, and clearer outliers.*
>
> **Two, an afternoon and evening admission checklist.** That 5 to 6% extra length of stay for 6pm to 10pm admissions tells us key reviews, medical, discharge planning, allied health, are getting pushed to the next morning. A structured trigger right at admission, kicking off the discharge plan and flagging what needs reviewing, could recover some of that time. *Operational impact: fewer wasted bed days, faster patient flow.*
>
> **Three, a targeted case review for the seven F41B episodes.** These patients stayed far longer than the model expected, without the clinical complexity to explain it. A case-by-case review would surface what's actually going on, system delays, communication breakdowns, social factors. *Patient care impact: finds and fixes what's actually delaying these patients' discharge.*
>
> I ordered these by scope. The first is a system-level change to benchmarking. The second is an operational protocol. The third is a targeted clinical intervention."

---

## CLOSING
**[Time: ~30 seconds]**

**Full script:**
> "So to sum up. After adjusting for DRG, three things independently explain longer length of stay: patient complexity, how the admission was arranged, and what time of day the patient arrived. The mixed effects model gives us a solid, interpretable framework that can directly support risk-adjusted benchmarking at a hospital.
>
> Happy to go deeper into any part of this, the modelling decisions, the EDA, or the recommendations. Thank you."

---
---

# Q&A PREPARATION
**15 questions covering all four brief requirements**

---

### DATASET & EDA

**1. Why did you choose LOS as your modelling subject rather than, say, readmissions or cost?**
> The EDA drove this decision. Length of stay showed high variability across the dataset, was partially but not fully explained by case mix, and had clear operational angles worth digging into. All three of those are needed for a useful modelling target. Readmissions weren't visible in this dataset without a patient level linkage key. Cost wasn't in the HCP data at all. So length of stay was both tractable and high impact, it's a direct driver of bed occupancy, staffing, and revenue recovery.

**2. Why did you exclude same-day episodes?**
> Same-day episodes have a length of stay of zero by definition. They're a completely different clinical pathway to begin with, things like day surgery or outpatient procedures. Including them would create a bimodal outcome distribution that one regression model can't handle cleanly. If the question extended to that population, a separate model for same-day episodes would make more sense.

**3. You didn't have ICU data. How does that affect your conclusions?**
> ICU episodes are typically captured within the higher acuity DRGs, so the random DRG intercept partially absorbs that variation. But within a given DRG, a patient who went to ICU versus one who didn't is a real difference the model can't see. I flagged this as a limitation. Estimates for high acuity DRGs like E62A should be read knowing ICU status isn't controlled for. If ICU data were available, it would be a strong candidate to add.

**4. What does the "Not Assigned" finding mean operationally?**
> To be precise, "Not Assigned" is a value in the urgency of admission field, not the referral source field, their referral source is fully recorded. So this isn't a group with an unclear background, it's a group with an unclear urgency status. And when I looked at their referral source, 75% came through A&E or transfer pathways, the same channels emergency patients typically come through, which is why their length of stay mirrors emergency admissions. Operationally, that means using Not Assigned as its own benchmark category will underestimate those patients' expected length of stay. So the recommendation is to reclassify them for benchmarking purposes while a coding audit happens on the urgency field specifically.

---

### MODEL METHODOLOGY

**5. Why a mixed-effects model rather than OLS with DRG fixed effects?**
> Two reasons. First, parsimony. The fixed effects DRG model needed 501 parameters versus 28 for the mixed effects model, for only a marginal gain in R squared, 0.677 versus 0.628. Second, conceptual fit. DRG is a natural grouping variable, we want to account for the variation between DRGs, not estimate a separate effect for each one. Random intercepts do this efficiently and they generalise to rare or new DRGs, which fixed effects can't do.

**6. Why log-transform LOS instead of modelling it directly?**
> Length of stay has a heavy right skew, median 2 days, mean 3.3, max 69. The log transformation stabilises the variance and reduces how much leverage the extreme values have. It also makes the coefficients readable as multiplicative percentage effects, which is more intuitive. Saying each additional diagnosis is associated with 7.4% longer length of stay is clearer than saying plus 0.18 days per diagnosis evaluated at the mean.

**7. What is the ICC and why does it matter?**
> The ICC is the Intraclass Correlation Coefficient, it quantifies what share of total variance sits between DRG groups rather than within them. An ICC of about 0.50 means half of all length of stay variation is explained by DRG alone. That validates the need for case mix adjustment. Without it, any comparison between wards, clinicians, or time periods is confounded by patient mix. It also tells us there's plenty of within DRG variation left to explain, and that's where the fixed effects come in.

**8. How did you handle model selection, which variables to include?**
> Three criteria. Clinical relevance, would a clinician expect this to matter. EDA findings, did the data show a relationship. And collinearity, is it measuring something another variable already captures. I excluded principal diagnosis because it's collinear with DRG, transfer provider because it duplicates referral source, and discharge variables because they occur after admission, which is data leakage. CCU was tested in a sensitivity analysis and left out of the main model because it's highly DRG specific.

---

### MODEL TESTING & PERFORMANCE

**9. How did you assess whether the model performs well?**
> Four lenses. One, AIC comparison across the three candidate models, the mixed effects model reduced AIC from 12,440 to 9,310 versus the no DRG baseline. Two, R squared, a conditional R squared of 0.628 compared to 0.404 without DRG. Three, diagnostic plots, residual distribution, QQ plot, random effects normality. And four, robustness checks, re-running with alternative variable sets and a negative binomial specification. The findings held up across all four.

**10. The residual tails are heavy, does that invalidate the results?**
> Not for an explanatory model. Heavy tails just mean the model has more error on the most extreme length of stay cases, which is expected given how skewed the outcome is. The central bulk of residuals behaves well, and that's what matters for the fixed effect estimates. If this were a prediction model forecasting an individual patient's stay, the tail behaviour would be a bigger concern. For estimating population average effects, the model holds up fine.

**11. How would you validate this model for ongoing use?**
> I'd test temporal stability, train on 2022 and validate on 2023, and check whether the effect sizes hold up. I'd also get clinicians to sense check the direction and size of the key findings against their own experience. If this extended to a multi-site setting, I'd add hospital as a second random intercept and compare site level random effects against known performance variation. And for ongoing monitoring, I'd re-estimate annually as new data comes in.

---

### FINDINGS & RECOMMENDATIONS

**12. The 7.4% per-diagnosis, is that a linear assumption? What if the relationship is non-linear?**
> The EDA showed a roughly monotonic relationship, with acceleration above 7 diagnoses. I modelled it as linear in the main model for interpretability and parsimony, which is a standard starting point. Adding a spline or quadratic term would be a natural next step, it would likely improve the fit slightly without changing the overall conclusion. I'd recommend that as a follow-up, especially if the model gets used for individual-level benchmarking where the non-linearity matters more.

**13. Why do afternoon/evening admissions have longer stays, but night admissions don't?**
> My interpretation is operational rather than clinical. Evening admissions, 6 to 10pm, miss the window for same-day medical review, allied health input, and discharge planning, and all of that effectively starts the next day instead, adding a lag. Night admissions, 10pm to 6am, tend to be higher acuity emergencies, so once you've adjusted for DRG and urgency, those cases may already benefit from structured overnight protocols that neutralise the timing effect. To confirm this, you'd want qualitative data on when the first medical review and discharge planning conversations happen.

**14. You recommend reviewing seven F41B episodes, isn't that a very small sample to draw conclusions from?**
> Absolutely, and that's exactly why I framed it as a case review rather than a policy recommendation. Seven episodes is too few for statistical inference, but it's exactly the right number for a targeted clinical conversation. The finding is that these patients stayed longer than their complexity predicts, and that's a testable hypothesis. A clinical review would confirm whether there's a recurring cause, a social factor, a communication breakdown, a system bottleneck. If a pattern shows up, it becomes a policy recommendation. If not, it just gets resolved at the individual case level.

**15. How would you explain the mixed-effects model to a clinical director with no statistics background?**
> I'd say something like, we compared patients within the same diagnosis category to control for how sick they were, so we're not penalising wards that treat more complex patients. Within those groups, we found three things that consistently predict longer stays: how many health conditions a patient has, whether their admission was planned in advance, and what time of day they arrived. The model adjusts for the fact that some diagnosis groups are inherently more complex, so we're only looking at what happens beyond that. You don't need to explain random intercepts, you just need to explain what the model controls for and what it finds.

---

*End of script and Q&A preparation.*
