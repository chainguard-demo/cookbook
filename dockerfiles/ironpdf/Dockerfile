FROM --platform=linux/amd64 cgr.dev/chainguard/dotnet-runtime:latest AS runtime
FROM --platform=linux/amd64 cgr.dev/chainguard/dotnet-sdk:latest-dev AS build
USER root
WORKDIR /src

COPY --from=runtime / /base-chroot
# Add IronPDF dependencies, approximated from IronPDF's debian dep lists
RUN apk add --no-cache --no-commit-hooks --no-scripts --root /base-chroot --no-cache \
      ca-certificates-bundle \
      libnss libnspr libudev \
      alsa-lib \
      libatk-1.0 libatk-bridge-2.0 at-spi2-core \
      cairo cups-libs dbus libdrm libexpat1 libfontconfig1 mesa-gbm \
      glib gtk-3 pango \
      libx11 libxcb libxcomposite libxdamage libxext libxfixes libxkbcommon libxrandr \
      font-liberation

# Copy in .NET dependencies and then pull them in
COPY app/IronPdfPoc.csproj ./
RUN dotnet restore IronPdfPoc.csproj

# Add and compile the application in a new layer
COPY app/Program.cs ./
RUN dotnet publish IronPdfPoc.csproj -c Release --no-restore -o /publish

# Build the app into a minimal .NET runtime image with no `apk`
FROM --platform=linux/amd64 cgr.dev/chainguard/dotnet-runtime:latest

# Copy the chroot with all the dependencies, then copy the app on top of it 
COPY --from=build /base-chroot /

WORKDIR /app
COPY --from=build --chown=65532:65532 /publish/ ./

VOLUME ["/out"]
ENTRYPOINT ["dotnet", "/app/IronPdfPoc.dll"]
