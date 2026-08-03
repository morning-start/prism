//go:build unix

package daemon

import "syscall"

// setSocketUmask restricts newly created UDS sockets to the current user
// (ARCHITECTURE.md §5.2: umask 077).
func setSocketUmask() {
	syscall.Umask(0o077)
}
