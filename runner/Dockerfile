# syntax=docker/dockerfile:1.6

# Playwright base image — includes Node 20, Chromium, system dependencies.
# The -jammy variant is Ubuntu 22.04 based and supports multi-arch (amd64, arm64).
# Pinned to a specific version for reproducibility — bump explicitly, not via :latest.
FROM mcr.microsoft.com/playwright:v1.49.0-jammy

# /app: read-only application code (owned by root, pwuser can read but not write)
WORKDIR /app

# Copy only package files first to leverage Docker layer caching.
# If package.json doesn't change, the npm ci layer is reused on rebuild.
COPY package.json package-lock.json* ./

# Install dependencies as root.
# `npm ci` is preferred over `npm install` in containers — faster, deterministic,
# fails on lockfile drift.
RUN npm ci

# Copy the rest of the application.
# This layer is invalidated when test files change, but the slow npm ci layer above is preserved.
COPY . .

# Create a separate writable directory for test results, owned by pwuser.
#
# Two important details here:
# 1. We use /test-output/playwright (NOT /test-output directly). Playwright tries to
#    rmdir its output directory on each run. To rmdir a directory, Linux checks
#    permissions on the PARENT, not the directory itself. So we need pwuser to own
#    BOTH the parent (/test-output) AND the target (/test-output/playwright).
# 2. The chown -R is recursive, so it covers both.
#
# This separation (code in /app, results in /test-output) is also the production
# pattern for containerized test runners — code is immutable, mutable state lives
# in a dedicated volume-mountable directory. In Week 3, this becomes a K8s emptyDir.
RUN mkdir -p /test-output/playwright && chown -R pwuser:pwuser /test-output

# Drop to non-root user (provided by the Playwright base image).
# Running as non-root is a K8s security best practice and matches what production
# pod security policies expect.
USER pwuser

# Tell Playwright (via env var read in playwright.config.js) where to write results.
ENV PLAYWRIGHT_OUTPUT_DIR=/test-output/playwright

# Default command: run Playwright tests. The K8s Job spec can override this
# (e.g., to run a specific shard via --shard=1/4 in Week 3).
CMD ["npx", "playwright", "test"]