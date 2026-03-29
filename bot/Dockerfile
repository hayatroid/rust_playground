FROM elixir:1.18-slim AS build

ENV MIX_ENV=prod

WORKDIR /app

RUN apt-get update -y && apt-get install -y ca-certificates && apt-get clean
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY lib lib
RUN mix compile && mix release

FROM debian:trixie-slim
RUN apt-get update -y && apt-get install -y ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV PORT=8080

WORKDIR /app
COPY --from=build /app/_build/prod/rel/bot ./

CMD ["bin/bot", "start"]
