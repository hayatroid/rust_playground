defmodule Bot.Sandbox do
  require Logger

  @sandbox_url "http://rust-playground-sandbox.flycast"
  @time_limit_ns 30 * 1000 * 1000 * 1000
  @memory_limit_bytes 512 * 1024 * 1024
  @max_output_bytes 1024 * 1024
  @proc_limit 100
  @max_message_bytes 4000

  def run(code, on_stage \\ fn _ -> :ok end) do
    on_retry = fn -> on_stage.(:waiting_sandbox) end
    Req.get("#{@sandbox_url}/version", finch: Bot.Finch, receive_timeout: 60_000)
    on_stage.(:compiling)

    with {:ok, compiled} <- sandbox_run(
           ["rustc", "-O", "-o", "main", "main.rs"],
           copy_in: %{"main.rs" => %{"content" => code}},
           copy_out: ["stderr"],
           copy_out_cached: ["main"],
           on_retry: on_retry
         ) do
      case compiled["status"] do
        "Accepted" ->
          on_stage.(:running)

          sandbox_run(["./main"],
            copy_in: %{"main" => %{"fileId" => compiled["fileIds"]["main"]}},
            copy_out: ["stdout", "stderr"],
            on_retry: on_retry
          )

        "Nonzero Exit Status" ->
          {:compile_error, compiled["files"]["stderr"] || "compilation failed"}

        _ ->
          {:ok, compiled}
      end
    end
  end

  def format_result({:ok, result}) do
    stdout = result["files"]["stdout"] || ""
    stderr = result["files"]["stderr"] || ""
    time = max(result["time"] || 0, result["runTime"] || 0) |> div(1000 * 1000)
    memory = div(result["memory"] || 0, 1024)

    output =
      [{stdout, "stdout"}, {stderr, "stderr"}]
      |> Enum.reject(fn {s, _} -> s == "" end)
      |> Enum.map(fn {s, label} -> "**#{label}**\n```\n#{truncate(s, @max_message_bytes)}\n```" end)
      |> Enum.join("\n")

    """
    #{output}
    | status | time | memory |
    |---|---|---|
    | #{result["status"]} | #{time} ms | #{memory} KB |
    """
    |> String.trim()
  end

  def format_result({:compile_error, msg}) do
    """
    **Compile Error**
    ```
    #{truncate(String.trim(msg), @max_message_bytes)}
    ```
    """
    |> String.trim()
  end

  def format_result({:error, msg}), do: "Error: #{msg}"

  defp sandbox_run(args, opts) do
    body = %{"cmd" => [
      %{
        "args" => args,
        "env" => opts[:env] || ["PATH=/usr/bin"],
        "files" => [
          %{"content" => ""},
          %{"name" => "stdout", "max" => @max_output_bytes},
          %{"name" => "stderr", "max" => @max_output_bytes}
        ],
        "cpuLimit" => @time_limit_ns,
        "clockLimit" => @time_limit_ns,
        "memoryLimit" => @memory_limit_bytes,
        "procLimit" => @proc_limit,
        "copyIn" => opts[:copy_in] || %{},
        "copyOut" => opts[:copy_out] || [],
        "copyOutCached" => opts[:copy_out_cached] || []
      }
    ]}

    sandbox_post(body, opts[:on_retry] || fn -> :ok end)
  end

  defp sandbox_post(body, on_retry, retries \\ 10) do
    case Req.post("#{@sandbox_url}/run", finch: Bot.Finch, receive_timeout: 120_000, json: body) do
      {:ok, %{status: 200, body: [result]}} ->
        {:ok, result}

      {:ok, %{status: status}} when status in [502, 503] and retries > 0 ->
        Logger.info("sandbox #{status}, retrying (#{retries - 1} left)")
        on_retry.()
        Process.sleep(3000)
        sandbox_post(body, on_retry, retries - 1)

      {:ok, %{status: status, body: body}} ->
        {:error, "sandbox #{status}: #{inspect(body)}"}

      {:error, _reason} when retries > 0 ->
        on_retry.()
        Process.sleep(3000)
        sandbox_post(body, on_retry, retries - 1)

      {:error, reason} ->
        {:error, "sandbox unreachable: #{inspect(reason)}"}
    end
  end

  defp truncate(str, max) when byte_size(str) > max,
    do: String.slice(str, 0, max) <> "\n... (truncated)"
  defp truncate(str, _max), do: str
end
