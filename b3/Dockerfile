FROM python:2.7-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

# Point to Debian archive (Buster is EOL) and disable Valid-Until checks.
# set -eux is for error handing
# install dependencies like mariadb client
# old debian is required for old python packages
RUN set -eux; \
    printf "deb http://archive.debian.org/debian buster main\n" > /etc/apt/sources.list; \
    printf "deb http://archive.debian.org/debian-security buster/updates main\n" >> /etc/apt/sources.list; \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99-archive-expired; \
    apt-get -o Acquire::Check-Valid-Until=false update; \
    apt-get install -y --no-install-recommends \
      gcc make pkg-config \
      git \
      mariadb-client \
      libmariadb-dev-compat libmariadb-dev \
      ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Pin Py2.7-compatible tooling
RUN python -m pip install --no-cache-dir "pip==20.3.4" "setuptools<45" "wheel"

# Install just the MySQL driver
RUN pip install --no-cache-dir "mysqlclient==1.3.14"
# Common B3 runtime deps (Py2.7 compatible pins)
RUN pip install --no-cache-dir \
  "requests<3" "feedparser<6" "python-dateutil<3" "pytz<2020" "PyYAML<6" "configobj<6"

# Fetch B3 source (run from source tree)
RUN git clone --depth 1 https://github.com/kmstrube81/b3-UO-enhanced.git /opt/b3

# App layout
WORKDIR /app
RUN mkdir -p /app/conf /app/logs

COPY entrypoint.sh /entrypoint.sh
# Pretty sure this is handled by git Strip CRLF (Windows line endings) and make executable
#RUN sed -i "s/\r$//" /entrypoint.sh && chmod +x /entrypoint.sh
#Make executable
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/bin/bash","/entrypoint.sh"]


