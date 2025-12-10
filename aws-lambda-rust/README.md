# aws-lambda-rust
An example of using the Chainguard `rust` and `glibc-dynamic` images to build and run a containerized Rust application on AWS Lambda. 
- AWS only officially began support for Rust on AWS Lambda in [November 2025](https://aws.amazon.com/about-aws/whats-new/2025/11/aws-lambda-rust/) and as of December 2025, have not yet released documentation on how to create a custom AWS container runtime for Rust (whether it be using an AWS base image or a non AWS one).
- Hence, this example leverages a sample application from the [aws-lambda-rust-runtime repository](https://github.com/aws/aws-lambda-rust-runtime?tab=readme-ov-file#example-function) and Chainguard's [official documentation](https://images.chainguard.dev/directory/image/rust/overview#application-setup-for-end-users) for its `rust` image. 
- The `aws-lambda-rust-runtime` repo also contains the source for the required AWS Lambda runtime crate called `lambda_runtime` (see the Cargo.toml file for the version used in this example).

## Requirements

You should have these utilities installed:

- `aws`
- `docker`
- `jq`

## Usage

Export a name for your Lambda function. We'll use this value in later steps.

```
$ export FUNCTION_NAME=chainguard-rust-lambda
```

Login to AWS. This may be different depending on how you authenticate to AWS.

```
$ aws sso login
```

Export the AWS account ID and region. We'll use these values in later steps.

```
$ export AWS_REGION=us-west-2
$ export ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)
```

Create an AWS ECR repository.

```
$ aws ecr create-repository --repository-name "${FUNCTION_NAME}"
```

Login to AWS ECR.

```
$ aws ecr get-login-password \
    | docker login \
        --username AWS \
        --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

Build and push the image.

```
$ docker buildx build \
    --push \
    --platform linux/amd64 \
    --provenance=false \
    -t "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FUNCTION_NAME}:latest" \
    .
```

Create a role for the Lambda.

```
$ aws iam create-role \
  --role-name "${FUNCTION_NAME}" \
  --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'
```

Create the Lambda function.

```
$ aws lambda create-function \
  --function-name "${FUNCTION_NAME}" \
  --package-type Image \
  --code "ImageUri=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FUNCTION_NAME}:latest" \
  --role "arn:aws:iam::${ACCOUNT_ID}:role/${FUNCTION_NAME}"
```

Invoke the Lambda function.

```
$ aws lambda invoke --function-name ${FUNCTION_NAME}  --payload '{"firstName":"shucking"}' --cli-binary-format raw-in-base64-out /dev/stderr >/dev/null
```

You should see this output:
```
{"message":"Hello, shucking!"}
```

Optionally, you may invoke the function by providing an empty payload, as the application code will leverage a default value:

```
$ aws lambda invoke --function-name ${FUNCTION_NAME} /dev/stderr >/dev/null
```

You should now see this output:
```
{"message":"Hello, world!"}
```

You may see a timeout error upon first invocation after creating this function. The runtime image may not yet be cached near where the function runs, so it could take longer than the default 3 second timeout to set the function's execution environment. Just run the invoke command again.

## Clean Up

Delete the Lambda function.

```
$ aws lambda delete-function --function-name "${FUNCTION_NAME}"
```

Delete the IAM role.

```
$ aws iam delete-role --role-name "${FUNCTION_NAME}"
```

Delete the ECR repository.

```
$ aws ecr delete-repository --repository-name "${FUNCTION_NAME}" --force
```
