# Developer start

Offline DAoC **0.36**. One source tree builds all three editions.
The custom Sluaghbinder class is controlled by the server setting
`classes / enable_sluaghbinder`: on in 0.36b (and by default), off in 0.36.
0.36c is 0.36b plus the new client (`source/new-client`), which plays on the same server.

Read these first:
- [AGENTS.md](AGENTS.md): project rules and layout.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): how to build, test, deploy and package.
- [source/new-client/README.md](source/new-client/README.md): the new client's source and how to run it.
- [docs/LLM-QUICKSTART.md](docs/LLM-QUICKSTART.md): how to customize with your own AI assistant.

Work in a copy of your playable folder, keep saves out of commits, and report
automated tests separately from in-game checks.
