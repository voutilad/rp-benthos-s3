#!/bin/sh

curl \
    -X POST \
    -H "Authorization: Bearer $(cat auth/access_token)" \
    -d '{"fields": "[\"name\",\"identifier\"]","filters": "[{\"field\":\"namespace.identifier\",\"value\":0}]"}' \
    -L https://api.enterprise.wikimedia.com/v2/projects
