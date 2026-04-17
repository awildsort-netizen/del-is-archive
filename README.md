# Del is Archive

Tiny macOS menu bar helper that turns Delete into Archive in Apple Mail when the message list is focused.

Press Delete ⌫ to archive the selected message in Mail. Shift-Delete and text editing pass through unchanged.

## Install

Build and install the app into `/Applications`:

```sh
make install
```

Launch `/Applications/Del is Archive.app` before enabling Open at Login from the About window.

If macOS rejects the `/Applications` write, run:

```sh
sudo make install
```

## Development

Run from the command line:

```sh
make run
```

Build only:

```sh
make build
```

Create a downloadable zip:

```sh
make zip
```

Remove the installed app:

```sh
make uninstall
```

## Permissions

macOS needs permission before this can work:

- Accessibility: required for the event tap and focused-element checks.
- Automation: required when the app triggers Mail's `Message > Archive` command through System Events.

If Accessibility or Automation is not enabled, the app opens About instead of prompting at startup. About shows the current permission status and includes buttons to start each enable flow and open the right System Settings pane. The Accessibility enable flow resets this app's existing Accessibility entry first, which helps clear stale permissions after reinstalling or rebuilding.

## Behavior

- Intercepts Delete and Forward Delete only when Apple Mail is frontmost.
- Requires no Command, Control, Option, Shift, Fn, or Help modifier.
- Passes the key through in editable text, compose, and search contexts.
- Archives by invoking Mail's `Message > Archive` menu item through System Events.
- Shows a menu bar archive icon only while Mail is active.
- Briefly switches to a thumbs-up icon after a successful archive.
- Click the menu bar icon to open About.
- About includes Accessibility status, Open at Login, Animate Success Icon, and Quit.

## Known Limitations

- The Archive action currently expects Mail's English menu title: `Message > Archive`.
- Unsigned local builds may trigger normal macOS first-run warnings.
- The focused-element detection is intentionally conservative. If Mail changes its accessibility labels, Del is Archive may pass Delete through instead of archiving.

## Release Automation

`make zip` builds `dist/del-is-archive.zip`.

The GitHub Actions workflow in `.github/workflows/release.yml` uploads that zip as a build artifact on manual runs and attaches it to GitHub releases for tags matching `v*`.

## License

MIT. See [LICENSE](LICENSE).
