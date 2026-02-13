.PHONY: db reset schema test all down

DOCKER_PSQL = docker compose exec -T postgres psql -U postgres

# Start PostgreSQL container
db:
	docker compose up -d
	@echo "Waiting for PostgreSQL to be ready..."
	@until docker compose exec -T postgres pg_isready -U postgres > /dev/null 2>&1; do sleep 0.5; done
	@echo "PostgreSQL is ready."

# Drop and recreate public schema (clean slate)
reset: db
	@$(DOCKER_PSQL) -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" > /dev/null 2>&1
	@echo "Database reset."

# Load all SQL files (clean reload)
schema: reset
	@for f in sql/*.sql; do \
		$(DOCKER_PSQL) -v ON_ERROR_STOP=1 < "$$f" > /dev/null 2>&1; \
	done
	@echo "Schema loaded."

# Run all tests (assumes schema is loaded)
test:
	@for f in tests/*.sql; do \
		name=$$(basename "$$f" .sql); \
		if $(DOCKER_PSQL) -v ON_ERROR_STOP=1 < "$$f" > /dev/null 2>&1; then \
			echo "  PASS: $$name"; \
		else \
			echo "  FAIL: $$name"; \
			$(DOCKER_PSQL) < "$$f" 2>&1; \
			exit 1; \
		fi; \
	done
	@echo ""
	@echo "All tests passed."

# Full cycle: schema + test
all: schema test

# Stop and remove containers
down:
	docker compose down
