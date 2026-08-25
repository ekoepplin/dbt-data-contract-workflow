---
status: accepted
---

# VS Code-native Jupyter over a standalone JupyterLab server

We needed a reproducible, container-based notebook environment: clone the repo, open it elsewhere, and immediately have working notebooks. Two real options existed: (a) VS Code/Codespaces-native notebooks via the `ms-toolsai.jupyter` extension family, running against the devcontainer's existing `.venv` kernel; (b) a standalone JupyterLab server inside the container, port-forwarded, reachable from any browser regardless of editor.

We chose (a). This repo is already devcontainer/VS Code-first (`customizations.vscode.extensions` already lists dbt, Python, and YAML extensions), so this adds no new moving parts — no long-running server process, no forwarded port, no auth/token decision. The kernel is simply the same `.venv` already used by `dbt`/`dlt`/`datacontract-cli`.

**Considered and rejected**: a standalone JupyterLab server — rejected because it trades simplicity for browser-only access that nobody asked for. It can be added later if a non-VS-Code workflow becomes necessary.

**Consequence**: notebooks are only directly usable from VS Code, Codespaces, or another devcontainer-CLI-compatible editor — not from a plain browser pointed at the container. Revisit this decision if browser-only/no-editor access is ever needed.
