# Makefile for k8s-test-runner — Phase 1, Week 3.
#
# Common workflow:
#   make doctor        — verify everything is in place
#   make demo          — full end-to-end: cluster, build, secret, jobs, aggregate
#   make aggregate     — re-aggregate the last (or specified) run
#
# Component targets:
#   make cluster-up    — start Kind cluster
#   make build         — build image and load into Kind
#   make secret        — create/refresh the K8s Secret from local creds file
#   make run           — render and apply the 4 per-user Jobs

.PHONY: demo doctor cluster-up cluster-down build secret run aggregate clean help

.DEFAULT_GOAL := help

help:
	@echo "k8s-test-runner — Phase 1, Week 3"
	@echo ""
	@echo "Setup:"
	@echo "  make doctor       Verify tools, credentials, and cluster state"
	@echo ""
	@echo "Pipeline (in order):"
	@echo "  make cluster-up   Create Kind cluster"
	@echo "  make build        Build image and load into Kind"
	@echo "  make secret       Create K8s Secret with AWS credentials"
	@echo "  make run          Apply 4 Jobs (one per Sauce demo user)"
	@echo "  make aggregate    Pull results from S3 and print summary"
	@echo ""
	@echo "Composed:"
	@echo "  make demo         Full pipeline: cluster + build + secret + run + aggregate"
	@echo ""
	@echo "Teardown:"
	@echo "  make clean        Delete all Jobs (cluster stays up)"
	@echo "  make cluster-down Tear down Kind cluster entirely"

demo: cluster-up build secret run aggregate

doctor:
	@bash scripts/doctor.sh

cluster-up:
	@bash scripts/kind-up.sh

cluster-down:
	@bash scripts/kind-down.sh

build:
	@bash scripts/build-and-load.sh

secret:
	@bash scripts/create-secret.sh

run:
	@bash scripts/run-jobs.sh

aggregate:
	@set -a && \
		. ${HOME}/.k8s-test-runner-credentials && \
		set +a && \
		cd runner && node aggregate-results.js

clean:
	@kubectl delete jobs -l app=k8s-test-runner --ignore-not-found=true