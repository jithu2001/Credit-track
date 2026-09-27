// Package web embeds the browser frontend so the app ships as one executable.
package web

import "embed"

//go:embed static
var Files embed.FS
