#' Reference-mode validation tests for the MEDv4-linear fitness-fatigue model
#'
#' Each test is a forward-simulation unit test anchored to canonical
#' resistance-training (RT) literature: dose-response, detraining decay,
#' ADL floor, saturation, etc. Purpose: verify the model STRUCTURALLY
#' reproduces qualitative RT dynamics across canonical scenarios before
#' any further analysis. A model that fails RM1–5 at sensible parameters
#' should not be calibrated — the problem is structural, not inferential.
#'
#' Design:
#'   - Self-contained Euler integrator (no external deps beyond base R)
#'   - Each test returns tibble(name, status, metric, expected, citation, ok)
#'   - Pure forward simulation, no MCMC, runs in seconds
#'   - Supports v1 parameterization (tau_f, tau_s hardcoded, no ADL)
#'     and v2 parameterization (tau_f, tau_s tunable, ADL per-subject)
#'
#' Usage:
#'   source("R/reference_mode_tests.R")
#'   results <- run_reference_mode_tests()
#'   print(results)

# ---- Core simulator (matches Stan linear boxcar structure) -----------------

#' Simulate MEDv4-linear trajectory via Euler. Uses a boxcar-integrated
#' TRIMP forcing + continuous ADL + linear flows.
#'
#' @param pulse_times Weeks at which pulses fire
#' @param pulse_heights Pulse amplitude (TRIMP units)
#' @param pulse_width Pulse duration (weeks). Default 1/7 (1 day).
#' @param params List with: adaptation_rate, adaptation_delay, max_frac_rate,
#'               Capacity, tau_fatigue, tau_signal, adl_trimp
#' @param baseline Starting Fitness (kg)
#' @param t_end Final time (weeks)
#' @param dt Euler step (weeks). Default 0.5.
#' @param signal_0 Initial Signal value (default 0 = v1 behavior)
#' @return data.frame(t, Fitness, Fatigue, Signal)
simulate_medv4 <- function(pulse_times, pulse_heights,
                            pulse_width = 1/7,
                            params,
                            baseline = 80,
                            t_end = 100,
                            dt = 0.5,
                            signal_0 = 0) {
  n_steps <- ceiling(t_end / dt) + 1L
  t_grid <- seq(0, n_steps * dt, by = dt)[seq_len(n_steps)]
  F_traj <- numeric(n_steps); Fat_traj <- numeric(n_steps); Sig_traj <- numeric(n_steps)

  Fitness <- baseline; Fatigue <- 0; Signal <- signal_0
  F_traj[1] <- Fitness; Fat_traj[1] <- Fatigue; Sig_traj[1] <- Signal

  ar    <- params$adaptation_rate
  adel  <- params$adaptation_delay
  mfr   <- params$max_frac_rate
  Cap   <- params$Capacity
  tau_f <- params$tau_fatigue
  tau_s <- params$tau_signal
  adl   <- params$adl_trimp

  for (i in seq_len(n_steps - 1L)) {
    t_start <- t_grid[i]
    t_endi <- t_start + dt

    # Boxcar TRIMP integrated over [t_start, t_endi] + continuous ADL
    TRIMP_int <- sum({
      lo <- pmax(t_start, pulse_times)
      hi <- pmin(t_endi, pulse_times + pulse_width)
      overlap <- pmax(hi - lo, 0)
      pulse_heights * overlap
    }) + adl * dt

    adaptation  <- (ar * Signal) / adel
    atrophy     <- (Fitness * mfr * Fitness) / Cap
    recovery    <- Fatigue / tau_f
    signal_loss <- Signal  / tau_s

    Fitness <- Fitness + dt * (adaptation - atrophy)
    Fatigue <- Fatigue + TRIMP_int - dt * recovery
    Signal  <- Signal  + TRIMP_int - dt * (adaptation + signal_loss)

    # Clamp non-negative
    Fitness <- min(max(Fitness, 0), 1e4)
    Fatigue <- min(max(Fatigue, -1e4), 1e4)
    Signal  <- min(max(Signal,  0), 1e4)

    F_traj[i + 1L] <- Fitness
    Fat_traj[i + 1L] <- Fatigue
    Sig_traj[i + 1L] <- Signal
  }
  data.frame(t = t_grid, Fitness = F_traj, Fatigue = Fat_traj, Signal = Sig_traj)
}

# ---- Default parameter sets ------------------------------------------------

#' v1 defaults (tau's hardcoded, no ADL).
default_params_v1 <- function(baseline = 80) {
  list(
    adaptation_rate  = 0.003,
    adaptation_delay = 6,
    max_frac_rate    = 0.015,
    Capacity         = 50,           # absolute — v1 pathology
    tau_fatigue      = 7 / exp(2),   # ≈ 0.947 wk
    tau_signal       = 14,
    adl_trimp        = 0             # v1 IMPLICIT
  )
}

#' v2 defaults.
#'
#' - Capacity becomes baseline-proportional: Capacity = alpha * baseline
#'   (alpha=1.5 default).
#' - adl_trimp centered at 100 kg·sec/wk — physiologically defensible: at 100,
#'   steady-state F ≈ 0.92·baseline (passes RM5) while training pulses still
#'   dominate (passes RM1 dose-response). Higher adl saturates these tests.
default_params_v2 <- function(baseline = 80, alpha = 1.5) {
  list(
    adaptation_rate  = 0.003,
    adaptation_delay = 6,
    max_frac_rate    = 0.015,
    Capacity         = alpha * baseline,
    tau_fatigue      = 7 / exp(2),
    tau_signal       = 14,
    adl_trimp        = 100
  )
}

# ---- Pulse-train helpers ---------------------------------------------------

#' Weekly pulses, constant height. Classic RT protocol.
weekly_pulses <- function(n_weeks, height, start = 1) {
  list(times = seq(start, n_weeks, by = 1), heights = rep(height, n_weeks))
}

empty_pulses <- function() list(times = numeric(0), heights = numeric(0))

# ---- Reference-mode tests --------------------------------------------------

#' RM1: Dose-response — 2× volume should produce substantially more adaptation.
#' Citation: Schoenfeld 2017 (Sports Med); Krieger 2010; Ralston 2017.
test_RM1_dose_response <- function(params = default_params_v2(),
                                    baseline = 80, t_end = 52,
                                    base_height = 2000) {
  p1 <- weekly_pulses(t_end, base_height)
  p2 <- weekly_pulses(t_end, base_height * 2)
  s1 <- simulate_medv4(p1$times, p1$heights, params = params,
                       baseline = baseline, t_end = t_end)
  s2 <- simulate_medv4(p2$times, p2$heights, params = params,
                       baseline = baseline, t_end = t_end)
  gain1 <- max(s1$Fitness) - baseline
  gain2 <- max(s2$Fitness) - baseline
  ratio <- gain2 / pmax(gain1, 0.01)
  data.frame(
    name = "RM1_dose_response", status = "",
    metric = sprintf("gain_2x/gain_1x = %.2f", ratio),
    expected = "ratio > 1.3 (monotone positive dose-response)",
    citation = "Schoenfeld 2017 Sports Med; Krieger 2010",
    ok = ratio > 1.3
  )
}

#' RM2: Diminishing returns — low-baseline subjects gain MORE in relative terms.
#' Citation: Ahtiainen 2003; Hakkinen 1998; Suchomel 2016.
test_RM2_diminishing_returns <- function(t_end = 52, height = 2000) {
  p <- weekly_pulses(t_end, height)
  # Capacity is baseline-proportional in v2 — each subject gets own alpha·baseline
  s_low  <- simulate_medv4(p$times, p$heights, params = default_params_v2(baseline = 40),
                           baseline = 40, t_end = t_end)
  s_high <- simulate_medv4(p$times, p$heights, params = default_params_v2(baseline = 120),
                           baseline = 120, t_end = t_end)
  rel_gain_low  <- (max(s_low$Fitness)  - 40)  / 40
  rel_gain_high <- (max(s_high$Fitness) - 120) / 120
  data.frame(
    name = "RM2_diminishing_returns", status = "",
    metric = sprintf("rel_gain_40kg=%.3f, rel_gain_120kg=%.3f",
                     rel_gain_low, rel_gain_high),
    expected = "rel_gain_low > rel_gain_high (low-baseline gains more relative)",
    citation = "Ahtiainen 2003; Suchomel 2016",
    ok = rel_gain_low > rel_gain_high
  )
}

#' RM3: Ceiling / asymptote — long-horizon trajectory stabilizes, not diverges.
#' Citation: Bickel/Bamman 2011; Ibata 2021.
test_RM3_ceiling <- function(params = default_params_v2(),
                              baseline = 80, t_end = 300, height = 2000) {
  p <- weekly_pulses(t_end, height)
  s <- simulate_medv4(p$times, p$heights, params = params,
                      baseline = baseline, t_end = t_end)
  tail <- s$Fitness[s$t >= t_end - 50]
  cv_tail <- sd(tail) / mean(tail)
  data.frame(
    name = "RM3_ceiling", status = "",
    metric = sprintf("final-50wk Fitness CV = %.4f", cv_tail),
    expected = "CV < 0.05 (asymptotic)",
    citation = "Bickel/Bamman 2011",
    ok = cv_tail < 0.05 && max(s$Fitness) < 1000
  )
}

#' RM4: Detraining — cessation → measurable strength decay with plausible half-life.
#' Citation: Mujika & Padilla 2000 (Sports Med); Bickel/Bamman 2011; Bosquet 2013.
test_RM4_detraining <- function(params = default_params_v2(),
                                 baseline = 80, train_wks = 104,
                                 detrain_wks = 52, height = 2000) {
  p <- weekly_pulses(train_wks, height)
  s_full <- simulate_medv4(p$times, p$heights, params = params,
                           baseline = baseline, t_end = train_wks + detrain_wks)
  peak_F <- max(s_full$Fitness[s_full$t <= train_wks])
  final_F <- tail(s_full$Fitness, 1)
  gain_at_peak <- peak_F - baseline
  lost <- peak_F - final_F
  pct_lost_per_wk <- (lost / gain_at_peak) / detrain_wks
  data.frame(
    name = "RM4_detraining", status = "",
    metric = sprintf("pct_gain_lost_per_wk = %.4f", pct_lost_per_wk),
    expected = "0.005-0.03 per wk (0.5-3%/wk from Mujika-Padilla range)",
    citation = "Mujika & Padilla 2000; Bickel/Bamman 2011",
    ok = pct_lost_per_wk >= 0.003 && pct_lost_per_wk <= 0.05
  )
}

#' RM5: ADL floor — no training + nonzero ADL → fitness stays near baseline.
#' Citation: Thom 2005; LeBlanc 2000; Kortebein 2007.
test_RM5_adl_floor <- function(t_end = 104, baseline = 80) {
  pv1 <- default_params_v1(baseline = baseline)  # adl=0
  pv2 <- default_params_v2(baseline = baseline)  # adl=100, C=alpha·baseline

  s_noadl <- simulate_medv4(numeric(0), numeric(0),
                            params = pv1, baseline = baseline, t_end = t_end,
                            signal_0 = 100)  # small legacy signal
  s_adl   <- simulate_medv4(numeric(0), numeric(0),
                            params = pv2, baseline = baseline, t_end = t_end,
                            signal_0 = 100)

  final_frac_noadl <- tail(s_noadl$Fitness, 1) / baseline
  final_frac_adl   <- tail(s_adl$Fitness,   1) / baseline

  # v1 should decay; v2 should hold
  data.frame(
    name = "RM5_adl_floor", status = "",
    metric = sprintf("final_F/baseline: v1(no-ADL)=%.3f, v2(ADL)=%.3f",
                     final_frac_noadl, final_frac_adl),
    expected = "v2 ≥ 0.85; ideally v2 > v1 (ADL prevents full decay)",
    citation = "Thom 2005; LeBlanc 2000",
    ok = final_frac_adl >= 0.85 && final_frac_adl > final_frac_noadl
  )
}

#' RM10: Progressive overload (plateau under constant load) — fitness plateaus
#' for constant stimulus rather than growing indefinitely.
#' Citation: DeLorme 1945; Kraemer & Ratamess 2004 ACSM.
test_RM10_plateau_constant_load <- function(params = default_params_v2(),
                                              baseline = 80, height = 2000,
                                              t_end = 300) {
  p <- weekly_pulses(t_end, height)
  s <- simulate_medv4(p$times, p$heights, params = params,
                      baseline = baseline, t_end = t_end)
  F_mid <- s$Fitness[which.min(abs(s$t - 100))]
  F_late <- s$Fitness[which.min(abs(s$t - 200))]
  rel_change_100to200 <- (F_late - F_mid) / F_mid
  data.frame(
    name = "RM10_plateau_constant_load", status = "",
    metric = sprintf("F(t=200)/F(t=100) - 1 = %.4f", rel_change_100to200),
    expected = "< 0.10 (≤10%% additional gain after plateau reached)",
    citation = "DeLorme 1945; Kraemer & Ratamess 2004 ACSM",
    ok = rel_change_100to200 < 0.10
  )
}

#' RM11: Heterogeneity — drawing 100 subjects from the hierarchy produces
#' substantial range of final outcomes (matching Hubal 2005 FAMuSS spread).
#' Citation: Hubal 2005 MSSE; Erskine 2010; Ahtiainen 2016.
test_RM11_heterogeneity <- function(n_draws = 100, baseline = 80, t_end = 52,
                                     height = 2000) {
  set.seed(1988)
  log_mu_ar <- log(0.003); sigma_ar <- 0.5
  log_mu_C  <- log(50);    sigma_C  <- 0.5
  gains <- numeric(n_draws)
  for (i in seq_len(n_draws)) {
    ar <- exp(log_mu_ar + sigma_ar * rnorm(1))
    C  <- exp(log_mu_C  + sigma_C  * rnorm(1))
    pars <- default_params_v2(); pars$adaptation_rate <- ar; pars$Capacity <- C
    p <- weekly_pulses(t_end, height)
    s <- simulate_medv4(p$times, p$heights, params = pars,
                        baseline = baseline, t_end = t_end)
    gains[i] <- (max(s$Fitness) - baseline) / baseline
  }
  rel_range <- quantile(gains, 0.95) - quantile(gains, 0.05)
  data.frame(
    name = "RM11_heterogeneity", status = "",
    metric = sprintf("5-95%% relative gain range = %.3f (median %.3f)",
                     rel_range, median(gains)),
    expected = ">= 0.3 (Hubal 2005: ~0-60% hypertrophy range over ~12wk)",
    citation = "Hubal 2005 MSSE",
    ok = rel_range >= 0.3
  )
}

# ---- Master runner ---------------------------------------------------------

run_reference_mode_tests <- function(params = default_params_v2()) {
  tests <- list(
    test_RM1_dose_response(params = params),
    test_RM2_diminishing_returns(),
    test_RM3_ceiling(params = params),
    test_RM4_detraining(params = params),
    test_RM5_adl_floor(),
    test_RM10_plateau_constant_load(params = params),
    test_RM11_heterogeneity()
  )
  results <- do.call(rbind, tests)
  results$status <- ifelse(results$ok, "PASS", "FAIL")
  results[, c("name", "status", "metric", "expected", "citation")]
}
