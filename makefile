FRONTEND_DIR = ./web
BACKEND_DIR = .

.PHONY: all build-frontend start-backend linux

all: build-frontend start-backend

build-frontend:
	@echo "Building frontend..."
	@cd $(FRONTEND_DIR) && bun install && DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat VERSION) bun run build

start-backend:
	@echo "Starting backend dev server..."
	@cd $(BACKEND_DIR) && go run main.go &

# 构建 Linux 64位版本（用于部署）
linux: build-frontend
	@echo "Building Linux binary..."
	$(eval export CGO_ENABLED=0)
	$(eval export GOOS=linux)
	$(eval export GOARCH=amd64)
	@cd $(BACKEND_DIR) && go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(shell cat VERSION)'" -o new-api main.go
	@echo "Build complete: ./new-api"
