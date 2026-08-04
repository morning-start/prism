module github.com/morning-start/prism/transport/daemon

go 1.26

require (
	github.com/coder/websocket v1.8.15
	github.com/morning-start/prism/wrappers/go v0.0.0
	google.golang.org/grpc v1.83.0
	google.golang.org/protobuf v1.36.11
)

require (
	github.com/tetratelabs/wazero v1.8.0 // indirect
	golang.org/x/net v0.55.0 // indirect
	golang.org/x/sys v0.45.0 // indirect
	golang.org/x/text v0.37.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa // indirect
)

replace github.com/morning-start/prism/wrappers/go => ../../wrappers/go
