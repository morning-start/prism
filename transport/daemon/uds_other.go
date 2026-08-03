//go:build !unix

package daemon

// setSocketUmask is a no-op on platforms without POSIX umask semantics
// (e.g. Windows AF_UNIX sockets; Named Pipe access is governed by the pipe
// ACL instead).
func setSocketUmask() {}
