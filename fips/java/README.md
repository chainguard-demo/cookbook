# SpringHelloWorld

A sample BouncyCastle FIPS applicataion using a Spring Boot Fat JAR.

The application is compiled as a Fat JAR and packaged into a JRE container image. The application shows an example of externalizing BouncyCastle modules in a FAT JAR to enforce the use of FIPS validated cryptography.

The externalized modules are highlighted in the src/main/resources/META-INF/MANIFEST.MF:
```bashc
cat src/main/resources/META-INF/MANIFEST.MF 
Manifest-Version: 1.0
Class-Path: /usr/share/java/bouncycastle-fips/bc-fips.jar 
            /usr/share/java/bouncycastle-fips/bctls-fips.jar 
            /usr/share/java/bouncycastle-fips/bcpkix-fips.jar 
            /usr/share/java/bouncycastle-fips/bcutil-fips.jar
```


## Build and run the project

```bash
mvn clean package
docker build -t springboot-fat-jar:fips .
docker run springboot-fat-jar:fips
NOTE: Picked up JDK_JAVA_OPTIONS: --add-exports=java.base/sun.security.internal.spec=ALL-UNNAMED --add-exports=java.base/sun.security.provider=ALL-UNNAMED -Djavax.net.ssl.trustStoreType=FIPS

  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
 :: Spring Boot ::                (v3.2.5)

2024-08-28T00:32:30.079Z  INFO 1 --- [           main] c.example.SpringHelloWorldApplication    : Starting SpringHelloWorldApplication using Java 17.0.12-internal with PID 1 (/home/build/app.jar started by root in /app)
2024-08-28T00:32:30.084Z  INFO 1 --- [           main] c.example.SpringHelloWorldApplication    : No active profile set, falling back to 1 default profile: "default"
2024-08-28T00:32:31.585Z  INFO 1 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8080 (http)
2024-08-28T00:32:31.598Z  INFO 1 --- [           main] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
2024-08-28T00:32:31.599Z  INFO 1 --- [           main] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.20]
2024-08-28T00:32:31.639Z  INFO 1 --- [           main] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
2024-08-28T00:32:31.640Z  INFO 1 --- [           main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 1434 ms
2024-08-28T00:32:31.766Z  WARN 1 --- [           main] .s.s.UserDetailsServiceAutoConfiguration : 

Using generated security password: 10d3665c-283b-4c95-8e45-1c0e70f591c7

This generated password is for development use only. Your security configuration must be updated before running your application in production.

2024-08-28T00:32:32.068Z  INFO 1 --- [           main] o.s.s.web.DefaultSecurityFilterChain     : Will secure any request with [org.springframework.security.web.session.DisableEncodeUrlFilter@6c1cfa53, org.springframework.security.web.context.request.async.WebAsyncManagerIntegrationFilter@4d68b571, org.springframework.security.web.context.SecurityContextHolderFilter@67e13bd0, org.springframework.security.web.header.HeaderWriterFilter@1cc680e, org.springframework.web.filter.CorsFilter@52b06bef, org.springframework.security.web.csrf.CsrfFilter@1687eb01, org.springframework.security.web.authentication.logout.LogoutFilter@5a1c3cb4, org.springframework.security.web.authentication.www.BasicAuthenticationFilter@6468a7b6, org.springframework.security.web.savedrequest.RequestCacheAwareFilter@2cae9b8, org.springframework.security.web.servletapi.SecurityContextHolderAwareRequestFilter@1457fde, org.springframework.security.web.authentication.AnonymousAuthenticationFilter@61bcbcce, org.springframework.security.web.access.ExceptionTranslationFilter@22eaa86e, org.springframework.security.web.access.intercept.FilterSecurityInterceptor@3289079a]
2024-08-28T00:32:32.227Z  INFO 1 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path ''
2024-08-28T00:32:32.243Z  INFO 1 --- [           main] c.example.SpringHelloWorldApplication    : Started SpringHelloWorldApplication in 2.661 seconds (process running for 3.21)
```

## Why is this an example necessary?

Spring Boot applications are typically packaged as "fat JARs," which bundle all necessary classes and dependencies within a single archive. When running a
Spring Boot application using the java -cp approach, the JVM may not correctly locate the application classes and dependencies due to the structure of the fat
JAR, where classes are nested under BOOT-INF/classes and libraries under BOOT-INF/lib.

If the BouncyCastle JARs are not explicity added to the Fat JAR Classpath by either including them as pom dependencies or externalizing the classpath at buildtime then you will receive errors such as:
```bash
org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'conversionServicePostProcessor' defined in class path resource [org/springframework/security/config/annotation/web/configuration/WebSecurityConfiguration.class]: Failed to instantiate [org.springframework.beans.factory.config.BeanFactoryPostProcessor]: Factory method 'conversionServicePostProcessor' threw exception with message: java.security.NoSuchAlgorithmException: RSA KeyFactory not available
```


