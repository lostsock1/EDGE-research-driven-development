# EDGE Gapped Lab — ephemeral experiment container
# Built once, reused; each experiment run is a fresh --rm container.
# Base: slim Python 3.12 with common research tools.

FROM python:3.12-slim

LABEL org.edge.lab="gapped-lab"
LABEL org.edge.version="1.0"

# System tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    build-essential \
    python3-dev \
    jq \
    yq \
    sqlite3 \
    graphviz \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Python research stack
RUN pip install --no-cache-dir \
    numpy \
    pandas \
    scipy \
    scikit-learn \
    matplotlib \
    seaborn \
    pytest \
    pytest-benchmark \
    httpx \
    pyyaml \
    rich \
    tqdm \
    pydantic \
    duckdb \
    pyarrow

# Lab user (not root)
RUN useradd --create-home --shell /bin/bash labuser

# Entrypoint: expects experiment script at /lab/experiment/run.sh or run.py
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod 755 /usr/local/bin/lab-entrypoint

USER labuser
WORKDIR /home/labuser
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
