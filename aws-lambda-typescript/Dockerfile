# Define custom function directory
ARG FUNCTION_DIR="/function"

# Define Chainguard org to pull images from
ARG CHAINGUARD_ORG="chainguard"

FROM cgr.dev/${CHAINGUARD_ORG}/node:latest-dev AS build-image

ARG FUNCTION_DIR

# Switch to root user to use apk
USER 0

# Install build dependencies
RUN apk update && apk add --no-cache cmake autoconf automake libtool python3 py3-setuptools

WORKDIR ${FUNCTION_DIR}

# Copy function code
COPY package.json index.ts ./

# Install Node.js dependencies
RUN npm install

# Install the runtime interface client
RUN npm install aws-lambda-ric

RUN npm run build

# Use the Distroless Chainguard node image as the runtime
FROM cgr.dev/${CHAINGUARD_ORG}/node:latest

ARG FUNCTION_DIR

# Set working directory to function root directory
WORKDIR ${FUNCTION_DIR}

# Copy the built app from the build stage
COPY --from=build-image ${FUNCTION_DIR} ${FUNCTION_DIR}

# Set runtime interface client as default command for the container runtime
ENTRYPOINT ["/usr/bin/npx", "aws-lambda-ric"]
# Pass the name of the function handler as an argument to th. runtime
CMD ["dist/index.handler"]