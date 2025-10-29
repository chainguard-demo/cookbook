# Define custom function directory
ARG FUNCTION_DIR="/function"

# Define Chainguard org to pull images from
ARG CHAINGUARD_ORG="chainguard"

FROM cgr.dev/${CHAINGUARD_ORG}/node:latest-dev AS build-image

# Include global arg in this stage of the build
ARG FUNCTION_DIR

# Switch to root user to use apk
USER 0

# Install build dependencies
RUN apk update && apk add --no-cache cmake autoconf automake libtool python3 py3-setuptools

# Copy function code
RUN mkdir -p ${FUNCTION_DIR}
COPY . ${FUNCTION_DIR}

WORKDIR ${FUNCTION_DIR}

# Install Node.js dependencies
RUN npm install

# Install the runtime interface client
RUN npm install aws-lambda-ric

# Use the Distroless Chainguard node image as the runtime
FROM cgr.dev/${CHAINGUARD_ORG}/node:latest

# Required for Node runtimes which use npm@8.6.0+ because
# by default npm writes logs under /home/.npm and Lambda fs is read-only
ENV NPM_CONFIG_CACHE=/tmp/.npm

# Include global arg in this stage of the build
ARG FUNCTION_DIR

# Set working directory to function root directory
WORKDIR ${FUNCTION_DIR}

# Copy in the built dependencies
COPY --from=build-image ${FUNCTION_DIR} ${FUNCTION_DIR}

# Set runtime interface client as default command for the container runtime
ENTRYPOINT ["/usr/bin/npx", "aws-lambda-ric"]
# Pass the name of the function handler as an argument to the runtime
CMD ["index.handler"]
