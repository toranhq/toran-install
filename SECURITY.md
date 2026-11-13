# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately through GitHub: on this repository's **Security** tab, choose
**Report a vulnerability**. Include what you found, how to reproduce it, and the script version
(the `TORAN_INSTALLER_RELEASE` line at the top of each script).

We acknowledge a report within three business days and keep you informed until it is resolved.

## Scope

- The install scripts in this repository and how `toran.run` serves them.
- The Toran binary they install: report it here too, and we route it.

## Verifying what you run

Each script downloads the Toran binary for your platform and checks its SHA-256 against the
release before running it. To read a script before running it:

```sh
curl -fsSL https://toran.run/install.sh | less
```

```powershell
irm https://toran.run/install.ps1
```
