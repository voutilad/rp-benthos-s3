# Redpanda Connect -- The Unsexy ETL demo

It's pretty common that folks building streaming platforms still need
to onboard batches of data, often provided by 3rd parties via cloud
object storage. A pattern I've come across:

  1. 3rd party packages up structured data (xml, json, etc.) into
     archive like a compressed tarball.
  2. 3rd party uploads it to a bucket in S3, GCS, Azure Blob, etc.
  3. Streaming platform relies on some scheduled or triggered service
     to process the data.
  4. Data ends produced into a topic for downline consumption.

Using things like Apachi Nifi, Apache Flink, or Apache Kafka Connect
to address step 3 is often:
  - overkill -- platforms like Flink *can* do batch processing, but
    work best for stateful stream transformations
  - painful -- you need to deploy and manage backing infrastructure
    due to _n_-tiered design (e.g. control vs. task nodes)


## Enter Redpanda Connect

Since cloud providers all have some form of triggerable serverless
application frameworks where some code can be invoked automatically
when an object appears in a bucket, the simplest way to package up the
ETL would be in a single "lambda function" app invoked on-demand and
only when needed.

Luckily, Redpanda Connect (f.k.a. Benthos) scales down quite well!

So, why not just trigger a Redpanda Connect "job" using AWS Lambda?

The original Benthos project supported "serverless" deployments, but
assumed you wanted to develop a pipeline and output strategy based on
processing just the incoming raw event from the trigger. In this case,
that means we still need to go fetch the object in S3...and currently
there's no processor for that.

However! There *is* an AWS S3 `input`. We just need to programatically
configure it.


## High-level Design

This project provides a 2-phase approach to processing S3 objects on
creation:

  1. `http.yaml` -- an "outer" RP Connect configuration uses
     `http_client` inputs and outputs to receive and response to the
     AWS Lambda service, receiving the event when triggered and
     providing a response when completed. It takes the event data and
     calls out to...
  2. `config.yaml` -- an "inner" RP Connect configuration that uses
     `aws_s3` input and `kafka_franz` output along with a processing
     pipeline to do the unpacking and transformation of the gzipped
     tarballs of json documents.

## Low-level Design

1. 3rd party service generates gzipped tarball of _ndjson_
   (newline-delimitted JSON) files, each containing numerous JSON
   documents.
2. 3rd party uploads the file into the S3 bucket.
3. S3 bucket invokes Lambda function.
4. If one isn't running, AWS Lambda spins up an instance.
5. The "outer" logic polls the HTTP endpoint to retrieve the event,
   extracts details (e.g. bucket, object key, etc.) and invokes the
   "inner" logic using a `command` processor, overriding config used
   by the `aws_s3` input via cli args.
6. The "inner" logic retrieves the object, processes it, and publishes
   to a topic configured on the `kafka_franz` output
7. The "outer" logic takes over and sends an HTTP POST to let Lambda
   know the result (pass/fail) using an `http_client` output.


## Deployment

There are two phases to deployment:

1. Packaging up the application.
2. Deploying the AWS infrastructure.

### Packaging

You should be able to just run the `build.sh` script. It will package
up the Redpanda Connect configuration files (the yaml files), download
a particular Linux arm64 release of `rpk`, and assemble the Lambda
layer zip files.

For AWS, it's easiest to use the AWS environment variables for authentication. Grab those from your account and export them.


```sh
export AWS_ACCESS_KEY_ID="your-key-kid"
export AWS_SECRET_ACCESS_KEY="some-access-key"
export AWS_SESSION_TOKEN="you-long-long-session-token"
```

If you make config changes, make sure to re-run `build.sh`.

### Deployment

Deployment uses Terraform / OpenTofu. All you need is an AWS account
you have permissions to create infrastructure in, including IAM
roles/policies, S3 buckets, and Lambda functions. You also should have
a Redpanda instance accessible from the Lambda function, so go grab
one at: https://cloud.redpanda.com/sign-up

To keep it simple, prepare a Terraform variables file `terraform.tfvars`:

```hcl
s3_bucket_name = "my-cool-bucket"
redpanda_bootstrap = "tktktktktktkt.any.us-east-1.mpx.prd.cloud.redpanda.com:9092"
redpanda_topic = "documents"
redpanda_username = "my-redpanda-user"
redpanda_password = "my-super-cool-password"
redpanda_use_tls = true
redpanda_delete_objects = true
```

Then fire off the deployment:

```sh
tofu apply
```

## Caveats

The terraform stuff probably won't pick up on zip file / layer
changes. I haven't tested that part. If you make a config change and
re-run `build.sh`, keep that in mind. It might be easiest to run `tofu
destroy` and then `tofu apply` to rebuild the environment.
