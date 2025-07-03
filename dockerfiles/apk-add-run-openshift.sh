FROM cgr.dev/chainguard-private/chainguard-base

ARG PACKAGES="curl wget"

RUN apk add --no-cache $PACKAGES && \
  for pkg in $PACKAGES; do \
    for f in $(apk info --contents --no-cache $pkg | sed '1d'); do \
      case "$f" in \
        var/lib/db/sbom/*) continue ;; \
      esac; \
      [ -e "/$f" ] || continue; \
      chgrp 0 "/$f"; \
      chmod g=u "/$f"; \
    done; \
  done
