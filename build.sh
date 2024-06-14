#!/bin/sh

# Vars only for call to aws api for creating services.
RP_CONNECT_NAME="${RP_CONNECT_NAME:-rp-connect-s3-demo}"
RP_CONNECT_ROLE="${RP_CONNECT_ROLE:-arn:aws:iam::569527441423:role/dv-ec2-benthos-s3-role}"
RP_CONNECT_BUCKET="${RP_CONNECT_BUCKET:-dv-rp-benthos}"
RP_CONNECT_REGION="${RP_CONNECT_REGION:-us-east-1}"

# Vars used by Redpanda Connect in addition to aws api calls.
export RP_CONNECT_DELETE_OBJECTS=true
export BENTHOS_CONFIG_PATH="/opt/config.yaml"

# Make sure we have the linux/arm64 version of rpk ready to go.
if [ ! -e "layers/rpk/bin/.rpk.ac-connect" ]; then
    mkdir -p "layers/rpk/bin" "layers/connect/bin"
    if [ ! -e "rpk-linux-arm64.zip" ]; then
        echo "downloading rpk/arm64 v24.1.7"
        curl -s -O \
             -L "https://github.com/redpanda-data/redpanda/releases/download/v24.1.7/rpk-linux-arm64.zip"
    fi
    unzip -q -u "rpk-linux-arm64.zip" "rpk" -d "layers/rpk/bin/"
    unzip -q -u "rpk-linux-arm64.zip" ".rpk.ac-connect" -d "layers/connect/bin/"
fi

# Update our app layer.
cp bootstrap layers/app
cp {config,http}.yaml layers/app

# Update or create our layer files.
for layer in "app" "rpk" "connect"; do
    echo "zipping layer ${layer}"
    # Use different args if we are trying to update an existing zip file.
    if [ -e "layers/${layer}.zip" ]; then
        ZIP_ARGS=-9ju;
    else
        ZIP_ARGS=-9j;
    fi
    zip -q ${ZIP_ARGS} -b /tmp "layers/${layer}.zip" layers/${layer}/* layers/${layer}/.*
done
