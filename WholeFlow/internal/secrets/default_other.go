//go:build !windows

package secrets

// Default returns the platform's best store. Outside Windows there is no
// OS-backed secret store in the standard library, so values are only encoded.
func Default() Store { return Plain{} }
