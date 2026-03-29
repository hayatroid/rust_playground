defmodule Bot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT") || "4000")

    children = [
      {Finch, name: Bot.Finch, pools: %{
        "http://rust-playground-sandbox.flycast" => [
          conn_opts: [transport_opts: [inet6: true]]
        ]
      }},
      {Bandit, plug: Bot.Router, port: port}
    ]

    opts = [strategy: :one_for_one, name: Bot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
