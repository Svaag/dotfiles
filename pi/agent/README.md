# Pi agent config

Dotfiles-safe Pi config from `~/.pi/agent`.

Tracked here:

- `settings.json`
- `models.json` with secrets replaced by environment-variable references
- `themes/claude-dark.json`
- `fastcontext-ripgrep-config`

Not tracked here:

- `auth.json` / OAuth tokens / API keys
- `trust.json`
- sessions and fastcontext trajectories
- installed package binaries or node modules

Install/update manually:

```bash
mkdir -p ~/.pi/agent/themes
cp settings.json ~/.pi/agent/settings.json
cp models.json ~/.pi/agent/models.json
cp themes/claude-dark.json ~/.pi/agent/themes/claude-dark.json
cp fastcontext-ripgrep-config ~/.pi/agent/fastcontext-ripgrep-config
```

`models.json` expects secrets such as `VENICE_API_KEY` to be provided through the environment or Pi auth storage.
