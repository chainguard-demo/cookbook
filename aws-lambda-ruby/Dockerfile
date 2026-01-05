# Define custom function directory
ARG LAMBDA_TASK_ROOT="/var/task"

# Define Chainguard org to pull images from
ARG CHAINGUARD_ORG

FROM cgr.dev/${CHAINGUARD_ORG}/ruby:3.3-dev AS build-image

ARG LAMBDA_TASK_ROOT

# Switch to root user to use apk
USER 0

# Bundler isn't intended to run as root, so we set the directory permissions for nonroot
RUN mkdir -p ${LAMBDA_TASK_ROOT} && chown -R 65532:65532 ${LAMBDA_TASK_ROOT}
WORKDIR ${LAMBDA_TASK_ROOT}

USER 65532

ENV GEM_HOME="${LAMBDA_TASK_ROOT}/.gem" \
	GEM_PATH="${LAMBDA_TASK_ROOT}/.gem" \
	BUNDLE_PATH="${LAMBDA_TASK_ROOT}/vendor/bundle" \
	BUNDLE_APP_CONFIG="${LAMBDA_TASK_ROOT}/.bundle" \
	PATH="${LAMBDA_TASK_ROOT}/.gem/bin:${PATH}"

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ${LAMBDA_TASK_ROOT}/

# Install Bundler and specified gems
RUN gem install bundler --no-document && bundle config set --local path 'vendor/bundle' && bundle install
RUN bundle binstubs aws_lambda_ric --path "${LAMBDA_TASK_ROOT}/bin"

# Copy function code
COPY lambda_function.rb ./

# Use the Distroless Chainguard ruby image as the runtime
FROM cgr.dev/${CHAINGUARD_ORG}/ruby:3.3

ARG LAMBDA_TASK_ROOT
WORKDIR ${LAMBDA_TASK_ROOT}

COPY --from=build-image ${LAMBDA_TASK_ROOT} ${LAMBDA_TASK_ROOT}

ENV GEM_HOME="${LAMBDA_TASK_ROOT}/vendor/bundle" \
	GEM_PATH="${LAMBDA_TASK_ROOT}/vendor/bundle:${LAMBDA_TASK_ROOT}/vendor/bundle/ruby/3.3.0" \
	BUNDLE_PATH="${LAMBDA_TASK_ROOT}/vendor/bundle" \
	BUNDLE_APP_CONFIG="${LAMBDA_TASK_ROOT}/.bundle" \
	RUBYOPT="-rbundler/setup" \
	PATH="${LAMBDA_TASK_ROOT}/vendor/bundle/ruby/3.3.0/bin:${PATH}"

# Set runtime interface client as default command for the container runtime
ENTRYPOINT [ "ruby", "-S", "aws_lambda_ric" ]

# Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "lambda_function.handler" ]
