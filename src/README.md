# Client architecture

Aeris is the WinUI 3 entry point. UI, view models, subscription processing and native IPC client will be implemented in separate components as their contracts are defined. The client must not implement networking or privileged operations itself.
