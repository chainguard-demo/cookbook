FROM mcr.microsoft.com/dotnet/sdk:9.0 as build-env

WORKDIR /app

COPY TestDotnetApp.csproj .
COPY Program.cs .

RUN dotnet publish -c Release -o out

FROM mcr.microsoft.com/dotnet/aspnet:9.0

ENV HOST 0.0.0.0
ENV PORT 8080

WORKDIR /app

COPY --from=build-env /app/out .

USER app

EXPOSE 8080

ENTRYPOINT ["dotnet", "TestDotnetApp.dll"]
