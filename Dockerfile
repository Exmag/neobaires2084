FROM barichello/godot-ci:4.5.1

ENV SERVER_MODE=1

WORKDIR /app

COPY . /app/project

RUN godot --headless --path /app/project --import || true

CMD ["godot", "--headless", "--path", "/app/project", "res://game_server.tscn"]
