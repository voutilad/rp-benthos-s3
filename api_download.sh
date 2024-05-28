#!/bin/sh

curl \
    -H "Authorization: Bearer $(cat auth/access_token)" \
    -L https://api.enterprise.wikimedia.com/v2/snapshots/enwiki_namespace_0/download \
    --output enwiki.tar.gz
