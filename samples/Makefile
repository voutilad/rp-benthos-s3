.PHONY:	clean

SAMPLES=sample-0.ndjson sample-1.ndjson

samples.tar.gz: samples.tar
	gzip -fk9 samples.tar

samples.tar: ${SAMPLES}
	tar -cf samples.tar ${SAMPLES}

clean:
	rm -f samples.tar*
