# MEDv4 — what the model says, in plain English

The MEDv4 model is a **three-stock** system-dynamics representation of how resistance training (RT) changes performance over weeks to months. It descends from a long lineage of fitness-fatigue models in exercise science — Banister 1975, Calvert 1976, Busso 1991/2003 — but adds an explicit **secondary signal** that gates adaptation.

## The three stocks

| Stock | What it represents | Typical timescale |
|---|---|---|
| **Fitness** (F) | Long-run accumulated adaptation. Roughly: "what is your trained capacity right now?" | Weeks → months |
| **Fatigue** (Fat) | Short-timescale recovery debt. Decays exponentially once training stops. | Days → 1–2 weeks |
| **Signal** (S) | Secondary mediator (think: anabolic/catabolic balance, sensitization). Gates how fast Fitness can grow. | Days → 1–2 weeks |

**Performance** is *not* one of the stocks. It's a derived quantity:

```
Performance(t) = Fitness(t) − α · Fatigue(t)
```

The coefficient α is the relative "weight" of fatigue against fitness. This is the same impulse-response idea that goes back to Banister 1975 — except here Fitness is itself a stock that grows in response to Signal, not directly to TRIMP.

## What drives the stocks

A training session is represented as a **TRIMP pulse** (Training Impulse — a heuristic unit roughly proportional to work done × duration). Pulses arrive at session times; the simulator turns the pulse sequence into a piecewise-constant forcing function.

The continuous **ADL term** (Activities of Daily Living) is added on top of training pulses — untrained baseline activity never goes to zero in normal humans. ADL is what makes the model converge to a non-zero steady state when training stops, which matches the empirical observation that detraining decays *towards* baseline, not toward zero.

## The ODE system (linear variant)

```
dF/dt   = (ar · S) / τ_adapt − (F − baseline) / τ_atrophy
dFat/dt = TRIMP(t) + adl − Fat / τ_fatigue
dS/dt   = mfr · Fat − S / τ_signal
```

Where:

- `ar` (adaptation_rate): how fast Signal converts into Fitness gain
- `τ_adapt` (adaptation_delay): the delay between a fatigue stimulus and an adaptation
- `τ_atrophy`: how fast Fitness erodes back to baseline without stimulus (often parameterized as a fraction of baseline rather than a separate time constant)
- `mfr` (max_frac_rate): how strongly Fatigue feeds Signal
- `τ_fatigue`, `τ_signal`: time constants for the two short-timescale stocks

The default parameter set in the simulator is hand-tuned to reproduce the qualitative shape of canonical RT progressions (8–16 weeks of training, plus detraining). It is **not** a calibrated fit — calibrating to real subject data is a separate workflow (see Roadmap in the README).

## What the seven reference modes test

Reference-mode validation is a discipline from the Forrester / Sterman tradition of system dynamics: before you trust a model's quantitative predictions, you check it qualitatively reproduces a list of behaviors that the science says it *must* reproduce. If it can't pass those forward-simulation gates at sensible parameter values, the structure is wrong — no amount of calibration will rescue it.

The seven tests in `R/reference_mode_tests.R`:

| # | Reference mode | What it checks | Citation anchor |
|---|---|---|---|
| **RM1** | Dose-response: 2× training volume → larger steady-state Fitness gain | Hellard 2005, Schoenfeld 2017 |
| **RM2** | Hard-easy: periodized loading produces higher peak than constant loading | Stone 2007 |
| **RM3** | Overtraining: excessive load suppresses Fitness via Fatigue accumulation | Meeusen 2013 |
| **RM4** | Detraining: Fitness decays after training stops, but not to zero | Mujika 2000 |
| **RM5** | ADL floor: untrained ≠ zero (baseline activity maintains nonzero F) | Bickel 2011 |
| **RM10** | Adaptation rate saturation: response is sublinear in dose at high training volumes | Hellard 2005 (Hill saturation) |
| **RM11** | Recovery saturation: Fatigue clears with a bounded time-constant regardless of dose | Banister 1975 |

A model that passes all seven is **plausible**. It is not necessarily *right* — that requires calibration against real data. But it can't be wildly wrong about the directions exercise physiology says it must move.

## Lineage

| Year | Author(s) | Contribution |
|---|---|---|
| 1975 | Banister, Calvert et al. | First fitness-fatigue impulse-response model. Two exponentially-decaying stocks driven by TRIMP, performance = F − k·Fat. |
| 1976 | Calvert et al. | Extended Banister to filter forms; IEEE Trans. SMC. |
| 1991 | Busso et al. | Added time-varying gain k₂(t) to handle the "blunted Banister" problem. |
| 2003 | Busso | k₂ becomes a filtered state — second-order Fatigue dynamics. MSSE-published. |
| 2000s | Sterman tradition | Cross-pollination of system-dynamics structural validation (reference modes) into physiology. |
| Today | MEDv4 (this model) | Three-stock variant with explicit Signal mediator, ADL term, and reference-mode-validated structural plausibility. |

## What this repo is *not*

- It is **not** a calibrated model fit to specific data. The parameter defaults are pedagogical, hand-tuned to make the qualitative shapes match the literature.
- It is **not** a recommendation engine for training programs. You can use the simulator to play out periodization scenarios, but the model's posterior uncertainty is enormous without calibration.
- It is **not** a replacement for working with a coach. The fitness-fatigue model is a conceptual tool, not a prescription oracle.

If a calibrated version becomes available, this repo will gain a `posterior/` layer and the explorer will ride along the calibrated parameter cloud instead of point estimates.
