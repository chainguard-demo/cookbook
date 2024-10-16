FROM cgr.dev/chainguard-private/jdk-fips:openjdk-17-dev

WORKDIR /home/build

COPY war-plugin-demo/ /home/build

USER 0
RUN apk add --no-cache maven
USER 65532

RUN mvn clean package

CMD ["mvn", "jetty:run"]
