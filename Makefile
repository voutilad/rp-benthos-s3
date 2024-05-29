.PHONY: clean samples

test: samples
	benthos -c config.yaml

samples:
	make -C samples

clean:
	make -C samples clean
