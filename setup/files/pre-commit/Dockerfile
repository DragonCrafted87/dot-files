FROM python:3.12-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends git gcc g++ make \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir pre-commit

WORKDIR /src
ENTRYPOINT ["pre-commit"]
