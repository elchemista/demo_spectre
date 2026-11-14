# Run after committing all ten repositories. This does not publish any commit.
root = Path.expand(List.first(System.argv()) || "..")
demo = Path.expand("..", __DIR__)
manifest = Path.join(demo, "spectre.lock.exs")
{pins, _} = Code.eval_file(manifest)

updated =
  Enum.map(pins, fn {name, pin} ->
    repo = Path.join(root, Atom.to_string(name))
    {dirty, 0} = System.cmd("git", ["-C", repo, "status", "--porcelain"])
    if String.trim(dirty) != "", do: raise("Commit #{name} changes before updating pins")
    {sha, 0} = System.cmd("git", ["-C", repo, "rev-parse", "HEAD"])
    {name, %{pin | ref: String.trim(sha)}}
  end)

{lock, _} = Code.eval_file(Path.join(demo, "mix.lock"))

lock =
  Enum.reduce(updated, lock, fn {name, %{git: git, ref: ref}}, acc ->
    Map.put(acc, name, {:git, git, ref, [ref: ref]})
  end)

header = "# Exact source revisions. Update: elixir scripts/update_spectre_pins.exs ../\n"

File.write!(
  manifest,
  header <>
    (updated
     |> inspect(pretty: true, limit: :infinity)
     |> Code.format_string!()
     |> IO.iodata_to_binary()) <> "\n"
)

lock_entries =
  lock
  |> Enum.sort()
  |> Enum.map_join("\n", fn {name, value} ->
    "  #{inspect(name)} => #{inspect(value, limit: :infinity, printable_limit: :infinity)},"
  end)

File.write!(Path.join(demo, "mix.lock"), "%{\n" <> lock_entries <> "\n}\n")

IO.puts(
  "Pinned ten committed repositories. Publish those commits before clean-clone verification."
)
