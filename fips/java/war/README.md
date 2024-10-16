# SpringHelloWorld

```bash
docker run --rm -it --net=host --entrypoint sh --user=0 -v $(pwd)/war-plugin-demo:/home/build cgr.dev/chainguard-private/jdk-fips:openjdk-17-dev
apk add --no-cache maven
mvn clean package
mvn jetty:run
```


