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

# Build our environment
LAMBDA_ENV=$(python3 lambda-env.py)

# Nuke old copy
echo "> deleting existing function, if any"
aws lambda delete-function \
    --region "${RP_CONNECT_REGION}" \
    --function-name "${RP_CONNECT_NAME}" \
    --output json \
    --no-cli-pager > /dev/null 2>&1

set -e

# Update layers and collect LayerVersionArn's.
LAMBDA_LAYERS=""
for layer in "rpk" "connect"; do
    echo "> publishing new layer for ${layer}"
    ARN=$(aws lambda publish-layer-version \
              --layer-name "rp-connect-demo-${layer}" \
              --zip-file "fileb://layers/${layer}.zip" \
              --region "${RP_CONNECT_REGION}" \
              --compatible-architectures "arm64" \
              --output json \
              --no-cli-pager \
              | jq -r .LayerVersionArn)
    LAMBDA_LAYERS="${ARN} ${LAMBDA_LAYERS}"
done
LAMBDA_LAYERS=$(echo "${LAMBDA_LAYERS}" | awk '{$1=$1};1')

# Deploy the function
echo "> creating function with layers: ${LAMBDA_LAYERS}"
LAMBDA_ARN=$(aws lambda create-function \
                 --region "${RP_CONNECT_REGION}" \
                 --timeout 300 \
                 --memory-size 512 \
                 --runtime provided.al2023 \
                 --architectures arm64 \
                 --layers ${LAMBDA_LAYERS} \
                 --handler not.used.for.provided.al2.runtime \
                 --role "${RP_CONNECT_ROLE}" \
                 --zip-file "fileb://layers/app.zip" \
                 --environment "${LAMBDA_ENV}" \
                 --function-name "${RP_CONNECT_NAME}" \
                 --no-cli-pager \
                 --output json \
                 | jq -r .FunctionArn)

echo "deployed ${LAMBDA_ARN}"
# Wire up the trigger
#NOTIFICATION="{\"LambdaFunctionConfigurations\": [{ \"LambdaFunctionArn\": \"${LAMBDA_ARN}\", \"Events\": [\"s3:ObjectCreated:*\"] }]}"

## MANUAL INTERVENTION REQUIRED FOR THE MOMENT
#aws s3api put-bucket-notification-configuration \
#    --region "${RP_CONNECT_REGION}" \
#    --bucket "${RP_CONNECT_BUCKET}" \
#    --notification-configuration "${NOTIFICATION}" \
#    --no-cli-pager \
#    --output json
