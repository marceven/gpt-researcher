# ------------------------------------------------------------------
# Stage 1  ─ Navegadores, toolchain de C/C++/Rust e utilitários extra
# ------------------------------------------------------------------
FROM python:3.11.4-slim-bullseye AS install-browser

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gnupg wget ca-certificates \
        build-essential clang cmake pkg-config libssl-dev \
        curl git ninja-build \
    \
    # ---- instala Rust (edition 2021+) ----
    && curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain stable && \
    echo 'export PATH=/root/.cargo/bin:$PATH' >> /etc/profile.d/rust.sh && \
    . /root/.cargo/env && \
    rustc --version && \
    \
    # ---- repositório + instalação do Chrome/Chromedriver ----
    ARCH=$(dpkg --print-architecture) && \
    wget -qO - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb [arch=${ARCH}] http://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends chromium chromium-driver firefox-esr && \
    chromium --version && chromedriver --version && \
    \
    # ---- Geckodriver ----
    GECKO_ARCH=$(case ${ARCH} in amd64) echo "linux64" ;; arm64) echo "linux-aarch64" ;; *) echo "linux64" ;; esac) && \
    wget https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-${GECKO_ARCH}.tar.gz && \
    tar -xvzf geckodriver-v0.36.0-${GECKO_ARCH}.tar.gz && \
    chmod +x geckodriver && mv geckodriver /usr/local/bin/ && \
    rm geckodriver-v0.36.0-${GECKO_ARCH}.tar.gz && \
    \
    # ---- limpeza ----
    rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.cargo/bin:${PATH}"

# ------------------------------------------------------------------
# Stage 2  ─ Instala dependências Python (inclui langchain‑google‑genai)
# ------------------------------------------------------------------
FROM install-browser AS gpt-researcher-install

ENV PIP_ROOT_USER_ACTION=ignore
WORKDIR /usr/src/app

# Copia e instala dependencies em camadas cacheáveis
COPY ./requirements.txt ./requirements.txt
COPY ./multi_agents/requirements.txt ./multi_agents/requirements.txt

RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt --upgrade --prefer-binary && \
    pip install --no-cache-dir -r multi_agents/requirements.txt --upgrade --prefer-binary && \
    # ---- integração Gemini ----
    pip install --no-cache-dir --upgrade --prefer-binary langchain-google-genai>=2.0.5

# ------------------------------------------------------------------
# Stage 3  ─ Imagem final, usuário não‑root e aplicação
# ------------------------------------------------------------------
FROM gpt-researcher-install AS gpt-researcher

# Configuração básica do servidor
ARG HOST=0.0.0.0
ENV HOST=${HOST}
ARG PORT=8000
ENV PORT=${PORT}
EXPOSE ${PORT}

ARG WORKERS=1
ENV WORKERS=${WORKERS}

# Cria usuário não‑root e define permissões
RUN useradd -ms /bin/bash gpt-researcher && \
    chown -R gpt-researcher:gpt-researcher /usr/src/app && \
    mkdir -p /usr/src/app/outputs && \
    chown -R gpt-researcher:gpt-researcher /usr/src/app/outputs && \
    chmod 777 /usr/src/app/outputs

USER gpt-researcher
WORKDIR /usr/src/app

# Copia o restante da aplicação
COPY --chown=gpt-researcher:gpt-researcher ./ ./

# Comando de inicialização
CMD uvicorn main:app --host ${HOST} --port ${PORT} --workers ${WORKERS}
