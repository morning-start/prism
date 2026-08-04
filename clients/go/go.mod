module github.com/morning-start/prism/clients/go

go 1.26

require (
	github.com/coder/websocket v1.8.15
	github.com/morning-start/prism/transport/daemon v0.0.0
	google.golang.org/grpc v1.83.0
)

require (
	github.com/morning-start/prism/wrappers/go v0.0.0 // indirect
	github.com/tetratelabs/wazero v1.8.0 // indirect
	golang.org/x/net v0.55.0 // indirect
	golang.org/x/sys v0.45.0 // indirect
	golang.org/x/text v0.37.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa // indirect
	google.golang.org/protobuf v1.36.11 // indirect
)

replace github.com/morning-start/prism/transport/daemon => ../../transport/daemon

replace github.com/morning-start/prism/wrappers/go => ../../wrappers/go
