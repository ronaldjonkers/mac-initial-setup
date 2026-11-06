# macinit.run

Static landing page for Mac Initial Setup. Serve this directory directly; no build step is needed.

The searchable catalog is a snapshot of `catalog.sh`. Refresh it after catalog changes:

```sh
./setup.sh --json | jq 'map(if .kind == "item" then del(.installed) else . end)' > site/catalog.json
```

`assets/setup-overview.png` is an interface screenshot from an earlier build. Update it when a current screenshot is available.
