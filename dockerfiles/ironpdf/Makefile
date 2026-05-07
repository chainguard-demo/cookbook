IMAGE      ?= ironpdf-poc
TAG        ?= dev
PLATFORM   ?= linux/amd64
OUT_DIR    ?= $(CURDIR)/out

.PHONY: help build run smoke clean

help: ## Show this help
	@awk 'BEGIN { FS = ":.*##" } /^[a-zA-Z_-]+:.*##/ { printf "  %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Build the image
	docker buildx build --platform $(PLATFORM) -t $(IMAGE):$(TAG) --load .

run: ## Run the image and write a PDF to ./out/hello.pdf
	@mkdir -p $(OUT_DIR)
	docker run --rm \
	  -e IRONPDF_LICENSE_KEY \
	  -v $(OUT_DIR):/out \
	  $(IMAGE):$(TAG)

smoke: build run ## Build then run, asserting a valid PDF was produced
	@test -s $(OUT_DIR)/hello.pdf || { echo "FAIL: $(OUT_DIR)/hello.pdf missing or empty"; exit 1; }
	@head -c 4 $(OUT_DIR)/hello.pdf | grep -q '%PDF' || { echo "FAIL: $(OUT_DIR)/hello.pdf is not a PDF"; exit 1; }
	@echo "OK: $(OUT_DIR)/hello.pdf is a valid PDF ($$(wc -c < $(OUT_DIR)/hello.pdf) bytes)"

clean: ## Remove built image and rendered PDFs
	-docker image rm $(IMAGE):$(TAG)
	rm -rf $(OUT_DIR)
