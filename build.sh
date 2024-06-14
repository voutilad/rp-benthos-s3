#!/bin/sh

REDPANDA_VERSION=v24.1.7
RELEASE_ARTIFACT=rpk-linux-arm64.zip
GITHUB_BASE_URL=https://github.com/redpanda-data/redpanda/releases/download

# Make sure we have the linux/arm64 version of rpk is ready to go.
if [ ! -e "layers/rpk/bin/.rpk.ac-connect" ]; then
    mkdir -p "layers/rpk/bin" "layers/connect/bin"
    if [ ! -e "${RELEASE_ARTIFACT}" ]; then
        echo "downloading rpk/arm64 ${REDPANDA_VERSION}"
        curl -s -O \
             -L "${GITHUB_BASE_URL}/${REDPANDA_VERSION}/${RELEASE_ARTIFACT}"
    fi
    unzip -q -u "${RELEASE_ARTIFACT}" "rpk" -d "layers/rpk/bin/"
    unzip -q -u "${RELEASE_ARTIFACT}" ".rpk.ac-connect" -d "layers/connect/bin/"
fi

# Update our app layer.
cp bootstrap layers/app
cp config.yaml layers/app
cp http.yaml layers/app

# Update or create our layer files.
for layer in "app" "rpk" "connect"; do
    echo "zipping layer ${layer}"
    # Use different args if we are trying to update an existing zip file.
    if [ -e "layers/${layer}.zip" ]; then
        ZIP_ARGS=-9ju;
    else
        ZIP_ARGS=-9j;
    fi
    zip -q ${ZIP_ARGS} -b /tmp "layers/${layer}.zip" \
        layers/${layer}/* layers/${layer}/.*
done
