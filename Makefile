# Makefile for k8s-test-runner.
#
# Common workflow:
#   make demo         — full end-to-end: cluster up, build, load, run, report
#   make cluster-up   — just start Kind
#   make build        — just build + load image
#   make run          — just run the Job (assumes image is already loaded)
#   make clean        — delete the Job (cluster stays up)
#   make cluster-down — tear down Kind cluster entirely

.PHONY: demo cluster-up cluster-down build run clean help

.DEFAULT_GOAL := help

help:
	@echo "k8s-test-runner — Phase 1, Week 2"
	@echo ""
	@echo "Targets:"
	@echo "  make demo         Full pipeline: cluster + build + load + run"
	@echo "  make cluster-up   Create Kind cluster"
	@echo "  make cluster-down Tear down Kind cluster"
	@echo "  make build        Build runner image and load into Kind"
	@echo "  make run          Apply Job and stream logs"
	@echo "  make clean        Delete the Job (cluster stays up)"

demo: cluster-up build run

cluster-up:
	@bash scripts/kind-up.sh

cluster-down:
	@bash scripts/kind-down.sh

build:
	@bash scripts/build-and-load.sh

run:
	@bash scripts/run-job.sh

clean:
	@kubectl delete job playwright-runner --ignore-not-found=true