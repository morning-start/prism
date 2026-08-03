module github.com/morning-start/prism/clients/go

go 1.26

require github.com/morning-start/prism/transport/daemon v0.0.0

require (
	github.com/coder/websocket v1.8.15 // indirect
	github.com/morning-start/prism/wrappers/go v0.0.0 // indirect
	github.com/tetratelabs/wazero v1.8.0 // indirect
)

replace github.com/morning-start/prism/transport/daemon => ../../transport/daemon

replace github.com/morning-start/prism/wrappers/go => ../../wrappers/go
