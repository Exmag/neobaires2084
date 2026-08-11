FROM ubuntu:22.04

# Tu versión exacta de Godot
ARG GODOT_VERSION=4.5.1-stable

ENV DEBIAN_FRONTEND=noninteractive
ENV SERVER_MODE=1

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl ca-certificates unzip \
    libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi1 \
    libgl1 libasound2 libfontconfig1 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

COPY . /app/project

RUN curl -L "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -o /tmp/godot.zip \
    && unzip /tmp/godot.zip -d /tmp/godot \
    && mv /tmp/godot/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot /tmp/godot.zip

RUN godot --headless --path /app/project --import || true

CMD ["godot", "--headless", "--path", "/app/project", "res://game_server.tscn"]
