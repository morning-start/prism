module github.com/morning-start/prism/transport/daemon

go 1.26

require (
	github.com/coder/websocket v1.8.15
	github.com/morning-start/prism/wrappers/go v0.0.0
)

require github.com/tetratelabs/wazero v1.8.0 // indirect

replace github.com/morning-start/prism/wrappers/go => ../../wrappers/go
