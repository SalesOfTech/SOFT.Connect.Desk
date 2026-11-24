# SOFT.Connect.Desk

Branded self-hosted remote support client by **Sales Of Tech**.

Development base: RustDesk **1.5.3** (`95cca3f66`). The next branded version is
`1.5.3-soft.1` (Flutter build 72). This is a preparation branch, not a published
update. Release gates are listed in [docs/release-1.5.3.md](docs/release-1.5.3.md).

- Product: **SOFT.Connect.Desk**
- Website: <https://connect.salesof.tech>
- Download page: <https://desk.salesof.tech>
- Platforms: Windows, macOS, and Linux
- Server order: `desk.salesof.tech`, `95.105.66.180`, `desk.salesoftech.com`

## Client roles

- **Support** — customer client. Incoming connections are enabled; the customer
  confirms each session unless unattended access is configured with a password.
- **Operator** — full client for Sales Of Tech specialists. It can initiate and
  receive connections.

The roles are selected at compile time with the mutually exclusive Cargo features
`soft-connect-support` and `soft-connect-operator`.

## GitHub Actions

Run **Build SOFT.Connect.Desk** from the Actions tab and select:

- role: `support`, `operator`, or `all`;
- platform: `windows`, `linux`, `macos`, or `all`.

Tag builds (`v*`) build both Support and Operator clients. macOS artifacts are ad-hoc signed,
not notarized, and do not require a paid Apple Developer Program membership.

## License and upstream

This project is distributed under the GNU Affero General Public License v3.0.
It is a branded derivative of the RustDesk open-source project. Copyright and
license notices from upstream and third-party components are retained.

The original upstream README is preserved at
[`docs/UPSTREAM-README.md`](docs/UPSTREAM-README.md).
