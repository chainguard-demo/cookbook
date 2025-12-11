# aws-lambda-go
An example of using the Chainguard `go` and `glibc-dynamic` images to build and run a containerized Go application on AWS Lambda as described in [this documentation](https://docs.aws.amazon.com/lambda/latest/dg/go-image.html#go-image-other)

## Requirements

You should have these utilities installed:

- `aws`
- `docker`
- `jq`

## Usage

Export a name for your Lambda function. We'll use this value in later steps.

```
$ export FUNCTION_NAME=chainguard-go-lambda
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
$ aws lambda invoke --function-name "${FUNCTION_NAME}" /dev/stderr >/dev/null
```

The output should look similar to this:
```
{"statusCode":200,"headers":null,"multiValueHeaders":null,"body":"\"Hello from Lambda!\""}
```

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
