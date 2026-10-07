//go:build !windows

package main

import (
	"context"
	"errors"
)

var errNoService = errors.New("Windows service management is only available on Windows; use 'run' (e.g. under systemd)")

func isWindowsService() bool                                     { return false }
func runAsService(string, func(ctx context.Context) error) error { return errNoService }
func installService(_, _, _, _ string, _ []string) (bool, error) { return false, errNoService }
func uninstallService() error                                    { return errNoService }
func startService() error                                        { return errNoService }
func stopService() error                                         { return errNoService }
func serviceStatus() (string, error)                             { return "not installed", nil }
func spawnHidden(string, []string, ...string) error              { return errNoService }
func installLogonTask(string, []string) error                    { return errNoService }
func removeLogonTask() error                                     { return errNoService }
func logonTaskStatus() (string, error)                           { return "not registered", nil }

func secureDataDir(string) error { return nil } // 0o700 from MkdirAll already applies
