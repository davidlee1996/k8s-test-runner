# syntax=docker/dockerfile:1.6

# Playwright base image — includes Node 20, Chromium, system dependencies.
# Pinned to a specific version for reproducibility.
FROM mcr.microsoft.com/playwright:v1.49.0-jammy

WORKDIR /app

# Copy package files first for layer caching.
COPY package.json package-lock.json* ./
RUN npm ci

# Copy the rest of the application.
COPY . .

# Create writable output directory.
# Use /test-output/playwright (not /test-output) because Playwright rmdir's
# its output directory at start. Linux requires permission on the parent dir
# to rmdir a child — so pwuser needs to own both /test-output AND its subdirectory.
RUN mkdir -p /test-output/playwright && chown -R pwuser:pwuser /test-output

# Make the entrypoint executable.
RUN chmod +x /app/entrypoint.sh

USER pwuser

ENV PLAYWRIGHT_OUTPUT_DIR=/test-output/playwright

# Replace simple `npx playwright test` with the entrypoint script,
# which runs tests AND uploads results to S3 regardless of test outcome.
CMD ["/app/entrypoint.sh"]