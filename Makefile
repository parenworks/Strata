SBCL     ?= sbcl
PREFIX   ?= /usr/local
BINDIR    = $(PREFIX)/bin
SERVICEDIR = /etc/systemd/system

VERSION  = $(shell grep ':version' strata.asd | head -1 | sed 's/.*"\(.*\)".*/\1/')
BINARY   = bin/strata

.PHONY: all build docs test clean install uninstall deploy \
        service-install service-enable service-start service-stop \
        service-status service-restart release help

all: build

build: ## Build the Strata executable
	@echo "Building Strata v$(VERSION)..."
	@mkdir -p bin
	$(SBCL) --non-interactive --load build.lisp
	@echo "Built: $(BINARY)"
	@ls -lh $(BINARY)

docs: ## Regenerate docs/API.org from docstrings
	@echo "Generating API documentation..."
	$(SBCL) --non-interactive \
		--eval '(asdf:load-system :strata)' \
		--load tools/api-doc.lisp \
		--eval '(strata/tools/api-doc:generate)' \
		--eval '(uiop:quit 0)'
	@echo "Wrote docs/API.org"

test: ## Run the test suite (placeholder until tests are wired)
	$(SBCL) --non-interactive \
		--eval '(asdf:load-system :strata)' \
		--eval '(format t "[strata] No test suite defined yet.~%")' \
		--eval '(uiop:quit 0)'

clean: ## Remove build artifacts and FASL cache
	rm -rf bin/
	rm -rf ~/.cache/common-lisp/sbcl-*/$(shell pwd)/
	@echo "Clean."

install: build ## Install binary to PREFIX/bin
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(BINARY) $(DESTDIR)$(BINDIR)/strata
	@echo "Installed strata to $(DESTDIR)$(BINDIR)/strata"

uninstall: ## Remove installed binary and service file
	rm -f $(DESTDIR)$(BINDIR)/strata
	rm -f $(DESTDIR)$(SERVICEDIR)/strata.service
	@echo "Uninstalled strata"

deploy: install service-install service-enable ## Build, install, and enable systemd service
	@echo ""
	@echo "Strata v$(VERSION) deployed."
	@echo "  Binary:  $(BINDIR)/strata"
	@echo "  Service: $(SERVICEDIR)/strata.service"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Create system user:  sudo useradd -r -s /usr/sbin/nologin -m -d /opt/strata strata"
	@echo "  2. Edit service file:   sudo vi $(SERVICEDIR)/strata.service  (set DB password)"
	@echo "  3. Start service:       sudo systemctl start strata"
	@echo "  4. Check logs:          sudo journalctl -u strata -f"

service-install: ## Install systemd service file
	install -d $(DESTDIR)$(SERVICEDIR)
	install -m 644 strata.service $(DESTDIR)$(SERVICEDIR)/strata.service
	systemctl daemon-reload
	@echo "Installed strata.service"

service-enable: ## Enable service to start on boot
	systemctl enable strata.service
	@echo "Enabled strata.service"

service-start: ## Start the service
	systemctl start strata.service
	@echo "Started strata.service"

service-stop: ## Stop the service
	systemctl stop strata.service
	@echo "Stopped strata.service"

service-restart: ## Restart the service
	systemctl restart strata.service
	@echo "Restarted strata.service"

service-status: ## Show service status
	systemctl status strata.service

release: build ## Create a release tarball
	@mkdir -p release
	tar czf release/strata-$(VERSION)-$(shell uname -m)-linux.tar.gz \
		-C bin strata \
		--transform 's,^,strata-$(VERSION)/,'
	@echo "Release: release/strata-$(VERSION)-$(shell uname -m)-linux.tar.gz"
	@ls -lh release/strata-$(VERSION)-$(shell uname -m)-linux.tar.gz

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
