# Simple FIPS War Test

```bash
docker build --no-cache -t war-fips:cgr -f Dockerfile .
docker run --net=host war-fips:cgr
```

Open Browser to http://localhost:8080/


