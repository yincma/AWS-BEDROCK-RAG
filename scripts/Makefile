# OPA Policy Automation Makefile
# Provides convenient targets for policy enforcement, reporting, and management

.PHONY: help test check enforce report dashboard clean all

# Default target
.DEFAULT_GOAL := help

# Variables
ENVIRONMENT ?= dev
ENFORCEMENT_LEVEL ?= strict
DRY_RUN ?= false
SCRIPT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
PROJECT_ROOT := $(shell dirname $(SCRIPT_DIR))
POLICIES_DIR := $(PROJECT_ROOT)/policies
REPORTS_DIR := $(PROJECT_ROOT)/reports
TERRAFORM_DIR := $(PROJECT_ROOT)/infrastructure/terraform

# Colors for output
RESET := \033[0m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
BLUE := \033[34m

# Help target
help: ## Display this help message
	@echo "$(BLUE)OPA Policy Automation Commands$(RESET)"
	@echo "================================"
	@echo ""
	@echo "$(GREEN)Core Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Variables:$(RESET)"
	@echo "  $(YELLOW)ENVIRONMENT$(RESET)      Target environment (default: dev)"
	@echo "  $(YELLOW)ENFORCEMENT_LEVEL$(RESET) Enforcement level: strict|warn|advisory (default: strict)"
	@echo "  $(YELLOW)DRY_RUN$(RESET)          Run in dry-run mode: true|false (default: false)"
	@echo ""
	@echo "$(GREEN)Examples:$(RESET)"
	@echo "  make check ENVIRONMENT=prod"
	@echo "  make enforce ENVIRONMENT=staging ENFORCEMENT_LEVEL=warn"
	@echo "  make report"
	@echo "  make dashboard"

# Prerequisites check
check-prerequisites: ## Check if required tools are installed
	@echo "$(BLUE)Checking prerequisites...$(RESET)"
	@command -v opa >/dev/null 2>&1 || { echo "$(RED)Error: OPA is not installed$(RESET)"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)Error: Terraform is not installed$(RESET)"; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo "$(RED)Error: jq is not installed$(RESET)"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "$(RED)Error: Python 3 is not installed$(RESET)"; exit 1; }
	@echo "$(GREEN)All prerequisites are installed$(RESET)"

# Test policies
test: check-prerequisites ## Run OPA policy unit tests
	@echo "$(BLUE)Running OPA policy tests...$(RESET)"
	@cd $(POLICIES_DIR) && opa test . -v
	@echo "$(GREEN)Policy tests completed$(RESET)"

# Test with coverage
test-coverage: check-prerequisites ## Run OPA policy tests with coverage report
	@echo "$(BLUE)Running OPA policy tests with coverage...$(RESET)"
	@cd $(POLICIES_DIR) && opa test . -v --coverage --format=json > $(REPORTS_DIR)/test-coverage.json
	@cd $(POLICIES_DIR) && opa test . -v --coverage
	@echo "$(GREEN)Coverage report saved to $(REPORTS_DIR)/test-coverage.json$(RESET)"

# Format policies
format: check-prerequisites ## Format OPA policy files
	@echo "$(BLUE)Formatting OPA policy files...$(RESET)"
	@find $(POLICIES_DIR) -name "*.rego" -type f | while read file; do \
		echo "Formatting $$file"; \
		opa fmt --write "$$file"; \
	done
	@echo "$(GREEN)Policy formatting completed$(RESET)"

# Lint policies
lint: check-prerequisites ## Lint OPA policy files
	@echo "$(BLUE)Linting OPA policy files...$(RESET)"
	@find $(POLICIES_DIR) -name "*.rego" -type f | while read file; do \
		echo "Checking $$file"; \
		opa fmt --list "$$file" || exit 1; \
	done
	@echo "$(GREEN)Policy linting completed$(RESET)"

# Quick policy check
check: check-prerequisites ## Run quick policy check for specified environment
	@echo "$(BLUE)Running policy check for $(ENVIRONMENT) environment...$(RESET)"
	@$(SCRIPT_DIR)/policy-check.sh $(ENVIRONMENT)

# Full policy enforcement
enforce: check-prerequisites ## Run full policy enforcement for specified environment
	@echo "$(BLUE)Running policy enforcement for $(ENVIRONMENT) environment...$(RESET)"
	@$(SCRIPT_DIR)/policy-enforcement.sh $(ENVIRONMENT) $(ENFORCEMENT_LEVEL) $(DRY_RUN)

# Dry run enforcement
dry-run: check-prerequisites ## Run policy enforcement in dry-run mode
	@echo "$(BLUE)Running policy enforcement in dry-run mode...$(RESET)"
	@$(SCRIPT_DIR)/policy-enforcement.sh $(ENVIRONMENT) $(ENFORCEMENT_LEVEL) true

# Generate policy reports
report: check-prerequisites ## Generate comprehensive policy reports
	@echo "$(BLUE)Generating policy reports...$(RESET)"
	@mkdir -p $(REPORTS_DIR)
	@python3 $(SCRIPT_DIR)/policy-report-generator.py \
		--terraform-dir $(TERRAFORM_DIR) \
		--policies-dir $(POLICIES_DIR) \
		--output-dir $(REPORTS_DIR) \
		--environments dev staging prod
	@echo "$(GREEN)Reports generated in $(REPORTS_DIR)$(RESET)"

# Generate report for specific environment
report-env: check-prerequisites ## Generate report for specific environment
	@echo "$(BLUE)Generating policy report for $(ENVIRONMENT)...$(RESET)"
	@mkdir -p $(REPORTS_DIR)
	@python3 $(SCRIPT_DIR)/policy-report-generator.py \
		--terraform-dir $(TERRAFORM_DIR) \
		--policies-dir $(POLICIES_DIR) \
		--output-dir $(REPORTS_DIR) \
		--environments $(ENVIRONMENT)
	@echo "$(GREEN)Report generated for $(ENVIRONMENT) in $(REPORTS_DIR)$(RESET)"

# Create policy dashboard
dashboard: report ## Create and update policy dashboard
	@echo "$(BLUE)Creating policy dashboard...$(RESET)"
	@if [ -f "$(REPORTS_DIR)/policy-dashboard.html" ]; then \
		echo "$(GREEN)Dashboard created: $(REPORTS_DIR)/policy-dashboard.html$(RESET)"; \
		echo "$(YELLOW)Open file://$(REPORTS_DIR)/policy-dashboard.html in your browser$(RESET)"; \
	else \
		echo "$(RED)Error: Dashboard creation failed$(RESET)"; \
		exit 1; \
	fi

# Serve dashboard locally
serve-dashboard: dashboard ## Serve dashboard on local web server
	@echo "$(BLUE)Starting local web server for dashboard...$(RESET)"
	@echo "$(YELLOW)Dashboard available at: http://localhost:8080$(RESET)"
	@cd $(REPORTS_DIR) && python3 -m http.server 8080

# Install OPA if not present
install-opa: ## Install OPA (Linux/macOS)
	@echo "$(BLUE)Installing OPA...$(RESET)"
	@if command -v opa >/dev/null 2>&1; then \
		echo "$(YELLOW)OPA is already installed: $$(opa version)$(RESET)"; \
	else \
		echo "Downloading OPA..."; \
		curl -L -o /tmp/opa https://openpolicyagent.org/downloads/v0.58.0/opa_linux_amd64_static; \
		chmod +x /tmp/opa; \
		sudo mv /tmp/opa /usr/local/bin/; \
		echo "$(GREEN)OPA installed successfully$(RESET)"; \
	fi

# Setup development environment
setup-dev: install-opa check-prerequisites ## Setup development environment
	@echo "$(BLUE)Setting up development environment...$(RESET)"
	@mkdir -p $(REPORTS_DIR)
	@mkdir -p $(PROJECT_ROOT)/logs
	@echo "$(GREEN)Development environment setup completed$(RESET)"

# Clean generated files
clean: ## Clean generated reports and temporary files
	@echo "$(BLUE)Cleaning generated files...$(RESET)"
	@rm -rf $(REPORTS_DIR)/*.json
	@rm -rf $(REPORTS_DIR)/*.html
	@rm -rf $(REPORTS_DIR)/*.txt
	@rm -rf $(PROJECT_ROOT)/logs/*.log
	@find $(TERRAFORM_DIR) -name "tfplan.*" -type f -delete
	@find $(TERRAFORM_DIR) -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "$(GREEN)Cleanup completed$(RESET)"

# Deep clean including terraform state
clean-all: clean ## Deep clean including Terraform state files
	@echo "$(BLUE)Performing deep cleanup...$(RESET)"
	@find $(TERRAFORM_DIR) -name "terraform.tfstate*" -type f -delete
	@find $(TERRAFORM_DIR) -name ".terraform.lock.hcl" -type f -delete
	@echo "$(GREEN)Deep cleanup completed$(RESET)"

# Validate configuration files
validate-config: check-prerequisites ## Validate policy configuration files
	@echo "$(BLUE)Validating configuration files...$(RESET)"
	@if [ -f "$(POLICIES_DIR)/enforcement-config.yaml" ]; then \
		python3 -c "import yaml; yaml.safe_load(open('$(POLICIES_DIR)/enforcement-config.yaml'))" && \
		echo "$(GREEN)enforcement-config.yaml is valid$(RESET)" || \
		echo "$(RED)enforcement-config.yaml has syntax errors$(RESET)"; \
	fi

# Check policy syntax
validate-policies: check-prerequisites ## Validate all policy file syntax
	@echo "$(BLUE)Validating policy syntax...$(RESET)"
	@find $(POLICIES_DIR) -name "*.rego" -type f | while read file; do \
		echo "Validating $$file"; \
		opa fmt "$$file" > /dev/null || { echo "$(RED)Syntax error in $$file$(RESET)"; exit 1; }; \
	done
	@echo "$(GREEN)All policies have valid syntax$(RESET)"

# Policy documentation
docs: ## Generate policy documentation
	@echo "$(BLUE)Generating policy documentation...$(RESET)"
	@echo "# OPA Policy Documentation" > $(POLICIES_DIR)/POLICIES.md
	@echo "" >> $(POLICIES_DIR)/POLICIES.md
	@echo "Auto-generated on $$(date)" >> $(POLICIES_DIR)/POLICIES.md
	@echo "" >> $(POLICIES_DIR)/POLICIES.md
	@for dir in security cost performance compliance; do \
		if [ -d "$(POLICIES_DIR)/$$dir" ]; then \
			echo "## $${dir^} Policies" >> $(POLICIES_DIR)/POLICIES.md; \
			echo "" >> $(POLICIES_DIR)/POLICIES.md; \
			find $(POLICIES_DIR)/$$dir -name "*.rego" -type f | while read file; do \
				echo "### $$(basename $$file .rego)" >> $(POLICIES_DIR)/POLICIES.md; \
				echo "" >> $(POLICIES_DIR)/POLICIES.md; \
			done; \
		fi; \
	done
	@echo "$(GREEN)Documentation generated: $(POLICIES_DIR)/POLICIES.md$(RESET)"

# Performance benchmark
benchmark: check-prerequisites ## Run policy evaluation performance benchmark
	@echo "$(BLUE)Running policy evaluation benchmark...$(RESET)"
	@time $(SCRIPT_DIR)/policy-check.sh $(ENVIRONMENT) > /dev/null
	@echo "$(GREEN)Benchmark completed$(RESET)"

# Security scan of policies
security-scan: check-prerequisites ## Run security scan on policy files
	@echo "$(BLUE)Running security scan on policies...$(RESET)"
	@find $(POLICIES_DIR) -name "*.rego" -type f -exec grep -l "allow.*true" {} \; | \
		while read file; do \
			echo "$(YELLOW)Warning: Permissive policy found in $$file$(RESET)"; \
		done
	@echo "$(GREEN)Security scan completed$(RESET)"

# All environments check
check-all: ## Run policy check for all environments
	@echo "$(BLUE)Running policy check for all environments...$(RESET)"
	@for env in dev staging prod; do \
		echo "$(YELLOW)Checking $$env environment...$(RESET)"; \
		$(SCRIPT_DIR)/policy-check.sh $$env; \
	done
	@echo "$(GREEN)All environment checks completed$(RESET)"

# All environments enforcement
enforce-all: ## Run policy enforcement for all environments
	@echo "$(BLUE)Running policy enforcement for all environments...$(RESET)"
	@for env in dev staging prod; do \
		echo "$(YELLOW)Enforcing policies for $$env environment...$(RESET)"; \
		$(SCRIPT_DIR)/policy-enforcement.sh $$env $(ENFORCEMENT_LEVEL) $(DRY_RUN); \
	done
	@echo "$(GREEN)All environment enforcement completed$(RESET)"

# Complete workflow
all: lint test validate-policies check report dashboard ## Run complete policy workflow
	@echo "$(GREEN)Complete policy workflow finished successfully$(RESET)"

# CI/CD integration
ci: lint test validate-policies check-all ## Run CI/CD pipeline checks
	@echo "$(GREEN)CI/CD pipeline checks completed$(RESET)"

# Show status
status: ## Show current policy enforcement status
	@echo "$(BLUE)Policy Enforcement Status$(RESET)"
	@echo "========================="
	@echo "Environment: $(ENVIRONMENT)"
	@echo "Enforcement Level: $(ENFORCEMENT_LEVEL)"
	@echo "Dry Run: $(DRY_RUN)"
	@echo "Policies Directory: $(POLICIES_DIR)"
	@echo "Reports Directory: $(REPORTS_DIR)"
	@echo "Terraform Directory: $(TERRAFORM_DIR)"
	@echo ""
	@if [ -d "$(REPORTS_DIR)" ] && [ "$$(ls -A $(REPORTS_DIR) 2>/dev/null)" ]; then \
		echo "$(GREEN)Recent Reports:$(RESET)"; \
		ls -la $(REPORTS_DIR)/*.json 2>/dev/null | head -5 || echo "No JSON reports found"; \
	else \
		echo "$(YELLOW)No reports found$(RESET)"; \
	fi

# Watch mode for development
watch: ## Watch for policy changes and re-run tests
	@echo "$(BLUE)Starting watch mode...$(RESET)"
	@echo "$(YELLOW)Watching $(POLICIES_DIR) for changes...$(RESET)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(RESET)"
	@while true; do \
		inotifywait -r -e modify,create,delete $(POLICIES_DIR) 2>/dev/null || \
		(sleep 2); \
		echo "$(YELLOW)Policy change detected, running tests...$(RESET)"; \
		make test; \
		echo "$(GREEN)Tests completed. Watching for more changes...$(RESET)"; \
	done