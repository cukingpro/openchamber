# syntax=docker/dockerfile:1
FROM node:24.13.1-bookworm AS base
WORKDIR /app

# Cài đặt bun thông qua npm (vì image node đã có sẵn npm)
RUN npm install -g bun

FROM base AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/desktop/package.json ./packages/desktop/
COPY packages/vscode/package.json ./packages/vscode/
RUN bun install --frozen-lockfile --ignore-scripts

FROM deps AS builder
WORKDIR /app
COPY . .
RUN bun run build:web

FROM base AS runtime

# Cài đặt các thư viện hệ thống cho Debian
# Thêm cấu hình repo chính thức để tải cloudflared
RUN apt-get update && apt-get install -y curl gnupg && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main" | tee /etc/apt/sources.list.d/cloudflared.list && \
    apt-get update && apt-get install -y \
    build-essential \
    python3 \
    openssh-client \
    git \
    less \
    cloudflared \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

# Tạo user openchamber
RUN useradd -m -s /bin/bash openchamber

# Chuyển sang user openchamber
USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g opencode-ai

WORKDIR /home/openchamber
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

# Đảm bảo copy script khởi chạy với quyền thực thi
COPY --chmod=755 scripts/docker-entrypoint.sh /app/openchamber-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/app/openchamber-entrypoint.sh"]
