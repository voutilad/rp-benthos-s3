# About the Sample Files

The files in this directory are gzipped tarballs of JSON data pulled
from the Wikimedia API and constitute a subset of data from Wikipedia
articles.

The prep work was as follows:

 - Get a Wikimedia Enterprise API account:
   https://enterprise.wikimedia.com
 - Use the Snapshot API to get some content from Wikipedia:
   https://enterprise.wikimedia.com/docs/snapshot/
 - Transform the resulting ndjson data into parts using `split(1)`
   (either part of GNU coreutils or your OS distro)
 - Use `tar(1)` to package up the ndjson files and `gzip(1)` them

The demo post-processes the ndjson into a subset of data, specifically
extracting out the _abstract_ fields and capturing metadata related to
the original wikipedia url.

All content in these files is provided under their various Creative
Commons licensing and attributable as appropriate.
