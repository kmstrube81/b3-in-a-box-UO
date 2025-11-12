FROM node:18-bookworm

ENV DEBIAN_FRONTEND=noninteractive

# install deps for skia-canvas/canvas-ish + ImageMagick
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        tini \
        python3 \
        make \
        g++ \
        pkg-config \
        libcairo2-dev \
        libpango1.0-dev \
        libjpeg-dev \
        libgif-dev \
        librsvg2-dev \
        libfreetype6-dev \
        fontconfig \
        ca-certificates \
        imagemagick \
    && rm -rf /var/lib/apt/lists/*

RUN fc-cache -f

ENV APP_DIR=/opt/xlrbot
WORKDIR $APP_DIR

# copy your project (adjust if you copy earlier)
COPY . $APP_DIR

# make sure your shipped binary is executable if it exists
RUN if [ -f /opt/xlrbot/src/bin/magick ]; then chmod +x /opt/xlrbot/src/bin/magick; fi

# copy/normalize entrypoint
RUN sed -i 's/\r$//' /opt/xlrbot/entrypoint.sh \
 && (head -c 3 /opt/xlrbot/entrypoint.sh | od -An -t x1 | grep -qi "ef bb bf" \
     && tail -c +4 /opt/xlrbot/entrypoint.sh > /opt/xlrbot/entrypoint.tmp && mv /opt/xlrbot/entrypoint.tmp /opt/xlrbot/entrypoint.sh || true) \
 && chmod +x /opt/xlrbot/entrypoint.sh

# drop to node user
RUN chown -R node:node /opt/xlrbot
USER node
ENV NODE_ENV=production

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/opt/xlrbot/entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=3s --retries=5 CMD \
  test -f /opt/xlrbot/health/ready && \
  find /opt/xlrbot/health/ready -mmin -0.1 >/dev/null 2>&1 || exit 1
