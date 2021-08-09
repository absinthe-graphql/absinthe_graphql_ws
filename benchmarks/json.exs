map = %{a: 1, b: 2, c: 3}
json = Jason.encode!(map)

medium_map =
  1..40
  |> Enum.reduce(%{}, fn _, acc ->
    key = for _ <- 1..10, into: "", do: <<Enum.random('0123456789abcdef')>>
    val = for _ <- 1..10, into: "", do: <<Enum.random('0123456789abcdef')>>
    Map.put(acc, key, val)
  end)

medium_json = Jason.encode!(medium_map)

large_map =
  1..1000
  |> Enum.reduce(%{}, fn _, acc ->
    key = for _ <- 1..10, into: "", do: <<Enum.random('0123456789abcdef')>>
    val = for _ <- 1..10, into: "", do: <<Enum.random('0123456789abcdef')>>
    Map.put(acc, key, val)
  end)

large_json = Jason.encode!(large_map)

Benchee.run(
  %{
    "small encode" => fn bench -> bench.lib.encode(map) end,
    "small decode" => fn bench -> bench.lib.decode(json) end,
    "medium encode" => fn bench -> bench.lib.encode(medium_map) end,
    "medium decode" => fn bench -> bench.lib.decode(medium_json) end,
    "large encode" => fn bench -> bench.lib.encode(large_map) end,
    "large decode" => fn bench -> bench.lib.decode(large_json) end
  },
  inputs: %{
    "Jason" => %{lib: Jason},
    "eljiffy" => %{lib: Eljiffy}
  }
)
