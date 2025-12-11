# aws-lambda-dotnet

An example of using the Chainguard `dotnet-sdk` and `dotnet-runtime` images to build and run a containerized Dotnet application on AWS Lambda.
- The first two instructions on the [official AWS documentation for using non-AWS dotnet images](https://docs.aws.amazon.com/lambda/latest/dg/csharp-image.html#csharp-image-clients) were used to setup a basic dotnet application according to AWS' template for custom runtimes.
- The application in the AWS template is a basic application that receives input and converts all applicable characters to uppercase.
- This example deviates from the rest of the instructions on the aforementioned documentation so as to not introduce additional tooling (`dotnet lambda`) to build and deploy the application and instead leverage common tooling such as `docker buildx` and `aws-cli`.

## Requirements

You should have these utilities installed:
- `aws-cli`
- `docker`
- `jq`

## Usage

Export a name for your Lambda function. We'll use this value in later steps.

```
$ export FUNCTION_NAME=chainguard-dotnet-lambda
```

Login to AWS. This may be different depending on how you authenticate to AWS.

```
$ aws sso login
```

Export the AWS account ID and region, as well as your Chainguard organization name. We'll use these values in later steps.

```
$ export AWS_REGION=us-west-2
$ export ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)
$ export CHAINGUARD_ORG=[insert your org name]
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
    --build-arg CHAINGUARD_ORG=${CHAINGUARD_ORG} \
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
$ aws lambda invoke --function-name "${FUNCTION_NAME}" --payload '"Hello, World!"' --cli-binary-format raw-in-base64-out /dev/stderr >/dev/null
```

You should see this output:
```
"HELLO, WORLD!"
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
