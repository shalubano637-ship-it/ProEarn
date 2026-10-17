FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl \
       git \
       unzip \
       xz-utils \
       zip \
       libglu1-mesa \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && git config --global --add safe.directory ${FLUTTER_HOME} \
    && flutter precache --web \
    && flutter config --no-analytics

RUN chown -R vscode:vscode ${FLUTTER_HOME}

USER vscode
WORKDIR /workspaces/ProEarn

RUN flutter --version
