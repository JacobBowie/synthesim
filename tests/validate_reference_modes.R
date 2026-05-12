# tests/validate_reference_modes.R
#
# Runs the RT reference-mode validation suite against the MEDv4-linear
# parameterization. Purpose: verify the simulator reproduces canonical
# RT dynamics across 7 forward-simulation scenarios. Runs in seconds.
#
# Usage (any R 4.x):
#   Rscript tests/validate_reference_modes.R

suppressPackageStartupMessages({
  library(ggplot2)
  if (requireNamespace("ggprism", quietly = TRUE)) library(ggprism)
})

source("R/reference_mode_tests.R")

cat("=== Reference-mode validation suite —",
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "===\n")
cat("    Source: docs/parameter_inventory_2026_04_24.md §8\n\n")

# ---- Run the suite under v2 defaults (ADL enabled) -------------------------
results <- run_reference_mode_tests()

# Pretty-print
cat("Results (v2 params, alpha=1.5, adl_trimp=100):\n")
for (i in seq_len(nrow(results))) {
  r <- results[i, ]
  marker <- if (r$status == "PASS") "[PASS]" else "[FAIL]"
  cat(sprintf("%s %-32s | %s\n", marker, r$name, r$metric))
  cat(sprintf("         expected: %s\n", r$expected))
  cat(sprintf("         citation: %s\n\n", r$citation))
}

n_pass <- sum(results$status == "PASS")
cat(sprintf("SUMMARY: %d/%d passed\n\n", n_pass, nrow(results)))

# ---- Save artifacts --------------------------------------------------------
out_dir <- "data/validation/reference_modes"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
saveRDS(results, file.path(out_dir, "results.rds"))
write.csv(results, file.path(out_dir, "results.csv"), row.names = FALSE)

# ---- Illustrative plots for key tests --------------------------------------
# RM1: side-by-side dose response
p1_low  <- weekly_pulses(52, 2000)
p1_high <- weekly_pulses(52, 4000)
s_low  <- simulate_medv4(p1_low$times,  p1_low$heights,
                         params = default_params_v2(), baseline = 80, t_end = 52)
s_high <- simulate_medv4(p1_high$times, p1_high$heights,
                         params = default_params_v2(), baseline = 80, t_end = 52)
s_low$dose  <- "1x"
s_high$dose <- "2x"
df_rm1 <- rbind(s_low, s_high)

theme_use <- if (requireNamespace("ggprism", quietly = TRUE)) ggprism::theme_prism(base_size = 11) else theme_bw()

p_rm1 <- ggplot(df_rm1, aes(t, Fitness, color = dose)) +
  geom_line(linewidth = 0.9) +
  labs(title = "RM1 — dose-response (Schoenfeld 2017)",
       subtitle = "2× training stimulus should produce ~2× rate of gain",
       x = "Week", y = "Fitness (kg)", color = "Dose") +
  theme_use
ggsave(file.path(out_dir, "RM1_dose_response.png"), p_rm1,
       width = 7, height = 4, dpi = 150)

# RM4: detraining curve
p4 <- weekly_pulses(104, 2000)
s_det <- simulate_medv4(p4$times, p4$heights,
                        params = default_params_v2(), baseline = 80, t_end = 156)
s_det$phase <- ifelse(s_det$t <= 104, "training", "detraining")
p_rm4 <- ggplot(s_det, aes(t, Fitness, color = phase)) +
  geom_line(linewidth = 0.9) +
  geom_vline(xintercept = 104, linetype = "dotted") +
  labs(title = "RM4 — detraining (Mujika & Padilla 2000; Bickel/Bamman 2011)",
       subtitle = "104wk training + 52wk cessation; expect gradual decay toward baseline",
       x = "Week", y = "Fitness (kg)", color = "Phase") +
  theme_use
ggsave(file.path(out_dir, "RM4_detraining.png"), p_rm4,
       width = 7, height = 4, dpi = 150)

# RM5: ADL floor comparison (v1 vs v2)
s_noadl <- simulate_medv4(numeric(0), numeric(0), params = default_params_v1(),
                          baseline = 80, t_end = 104, signal_0 = 100)
s_adl   <- simulate_medv4(numeric(0), numeric(0), params = default_params_v2(),
                          baseline = 80, t_end = 104, signal_0 = 100)
s_noadl$model <- "v1 (adl=0, C=50)"; s_adl$model <- "v2 (adl=100, C=1.5·baseline)"
df_rm5 <- rbind(s_noadl, s_adl)
p_rm5 <- ggplot(df_rm5, aes(t, Fitness, color = model)) +
  geom_line(linewidth = 0.9) +
  geom_hline(yintercept = 80, linetype = "dashed", color = "grey50") +
  labs(title = "RM5 — ADL floor (Thom 2005; LeBlanc 2000)",
       subtitle = "No training; only environmental stimulus. Only microgravity (adl=0) should give full decay.",
       x = "Week", y = "Fitness (kg)", color = "Model") +
  theme_use
ggsave(file.path(out_dir, "RM5_adl_floor.png"), p_rm5,
       width = 7, height = 4, dpi = 150)

cat("Artifacts in", out_dir, ":\n")
print(list.files(out_dir))
cat("=== Done at", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "===\n")
