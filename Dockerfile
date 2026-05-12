# syntax=docker/dockerfile:1
#
# synthesim — reproducible R + Python runtime for the MEDv4 explorer.
#
# Three entrypoints share one image:
#   1. shiny    (port 3838)  — the R Shiny app
#   2. marimo   (port 2718)  — the marimo notebook (editable)
#   3. validate              — runs the 7-test reference-mode validator
#
# Build:    docker build -t synthesim .
# Default:  docker run --rm -p 3838:3838 synthesim   # Shiny on http://localhost:3838

FROM rocker/r-ver:4.5.2

# --- System deps (slim: no LaTeX, no GIS, no cmdstan) -----------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev \
      libssl-dev \
      libxml2-dev \
      libfontconfig1-dev \
      libfreetype6-dev \
      libpng-dev \
      python3 \
      python3-pip \
      python3-venv \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --- R packages -------------------------------------------------------------
# Posit Public Package Manager serves Linux binaries on rocker/r-ver:noble,
# so installs are seconds, not minutes.
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest')); \
          install.packages(c('shiny', 'bslib', 'ggplot2', 'patchwork', \
                             'dplyr', 'tidyr', 'tibble', 'deSolve', \
                             'DiagrammeR'))"

# --- Python deps for the marimo notebook ------------------------------------
RUN python3 -m pip install --no-cache-dir --break-system-packages \
      marimo \
      numpy \
      matplotlib

# --- Project ----------------------------------------------------------------
WORKDIR /synthesim
COPY . /synthesim

EXPOSE 3838 2718

# Default entrypoint = Shiny. Override via `docker run synthesim <command>`.
CMD ["R", "-e", "shiny::runApp('inst/shiny/synthesim', host = '0.0.0.0', port = 3838)"]
