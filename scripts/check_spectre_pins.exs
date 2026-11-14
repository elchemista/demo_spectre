demo = Path.expand("..", __DIR__)
{pins, _} = Code.eval_file(Path.join(demo, "spectre.lock.exs"))
{lock, _} = Code.eval_file(Path.join(demo, "mix.lock"))

if length(pins) != 10 or length(Enum.uniq(Keyword.keys(pins))) != 10,
  do: raise("Expected core and exactly nine distinct package pins")

for {name, %{git: git, ref: ref}} <- pins do
  unless Regex.match?(~r/\A[0-9a-f]{40}\z/, ref), do: raise("Invalid SHA for #{name}")

  unless Map.get(lock, name) == {:git, git, ref, [ref: ref]},
    do: raise("mix.lock does not match spectre.lock.exs for #{name}; refresh pins")
end

IO.puts("All ten Spectre Git pins agree with mix.lock.")
