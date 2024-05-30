.PHONY: clean samples test rpk

RPK != which rpk

test: rpk samples
	@$(RPK) connect run config.yaml

rpk:
	@if [ "$(RPK)" = "" ]; then \
		echo "rpk is missing!"; exit 1; \
	fi
	@if ! $(RPK) connect help > /dev/null; then \
		echo "rpk is too old!"; exit 1; \
	fi
	@echo "using rpk at $(RPK)"

samples:
	@make -C samples

clean:
	@make -C samples clean
