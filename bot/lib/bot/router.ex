defmodule Bot.Router do
  use Plug.Router
  require Logger

  @traq_url "https://q.trap.jp/api/v3"
  @stages %{
    waiting_sandbox: ":loading: サンドボックス応答待ち...",
    compiling: ":loading: コンパイル中...",
    running: ":loading: 実行中..."
  }

  plug Plug.Logger
  plug :verify_token
  plug :match
  plug :dispatch

  defp verify_token(conn, _opts) do
    token = Plug.Conn.get_req_header(conn, "x-traq-bot-token") |> List.first()

    if token == System.get_env("VERIFICATION_TOKEN") do
      conn
    else
      conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end

  match _ do
    {:ok, body, _} = Plug.Conn.read_body(conn)
    event = Plug.Conn.get_req_header(conn, "x-traq-bot-event") |> List.first()
    Logger.info("event=#{event}")

    if event in ["DIRECT_MESSAGE_CREATED", "MESSAGE_CREATED"] do
      Task.start(fn -> handle_message(body) end)
    end

    send_resp(conn, 204, "")
  end

  defp handle_message(body) do
    with {:ok, %{"message" => %{"channelId" => ch, "plainText" => text, "user" => %{"bot" => false}}}} <- Jason.decode(body),
         [_, code] <- Regex.run(~r/```(?:rust|rs)?\n(.+?)```/s, text),
         {:ok, mid} <- post_message(ch, @stages[:waiting_sandbox]) do
      on_stage = fn stage -> edit_message(mid, @stages[stage]) end
      result = Bot.Sandbox.run(String.trim(code), on_stage)
      edit_message(mid, Bot.Sandbox.format_result(result))
    end
  end

  defp post_message(channel_id, content) do
    case traq_request(:post, "/channels/#{channel_id}/messages", %{content: content}) do
      {:ok, %{status: 201, body: %{"id" => id}}} -> {:ok, id}
      other -> Logger.error("post failed: #{inspect(other)}"); :error
    end
  end

  defp edit_message(message_id, content) do
    case traq_request(:put, "/messages/#{message_id}", %{content: content}) do
      {:ok, %{status: 204}} -> :ok
      other -> Logger.error("edit failed: #{inspect(other)}")
    end
  end

  defp traq_request(method, path, body) do
    Req.request(
      method: method,
      url: "#{@traq_url}#{path}",
      headers: [authorization: "Bearer #{System.get_env("BOT_ACCESS_TOKEN")}"],
      json: body
    )
  end
end
