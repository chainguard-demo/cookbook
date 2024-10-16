FROM cgr.dev/chainguard-private/jre-fips:openjdk-17-dev

USER 0
ENV LANG C.UTF-8
ENV JAVA_HOME=/usr/lib/jvm/default-jvm

COPY target/SpringHelloWorld-1.0-SNAPSHOT.jar /home/build/app.jar

ENTRYPOINT ["java", "-jar", "/home/build/app.jar"]


