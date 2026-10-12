# talos/schematics

[Talos Image Factory](https://factory.talos.dev) schematics, one per node.
Each file's comments explain its extension choices.

| Node | Schematic ID | Secure Boot |
|---|---|---|
| [`controlplane`](controlplane.yaml) | `2d61dd07b20062062ea671b4d01873506103b67c0f7a4c3fb6cf4ee85585dcb8` | no |
| [`media`](media.yaml) | `f31a9830aa99bde462c9e9e2f24480528d7a29d346013c306200b73a4ad5e331` | no |
| [`ai`](ai.yaml) | `520ffe248ea533c4ec6b81f4ce435d610371b2f7e1ec8896d4612345a810fe6f` | **yes** |

After editing a schematic, run `mise run talos:schematics` to register it and
print its ID and image URLs, then update the ID above. The Talos version comes
from `talosctl` in [`mise.toml`](../../mise.toml).

On the `ai` node, always use the `-secureboot` ISO and installer.
