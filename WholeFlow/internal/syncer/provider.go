package syncer

import (
	"fmt"
	"log/slog"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/cloud/memory"
	"wholeflow/internal/cloud/rest"
)

// ProviderFactory builds a cloud.Provider from settings. The engine calls it
// at the start of every run so configuration changes take effect immediately.
type ProviderFactory func(Settings) (cloud.Provider, error)

// NewProviderFactory returns the default factory. A memory provider is kept
// across runs so a dry run accumulates state like a real backend would.
func NewProviderFactory(log *slog.Logger, cloudTimeout time.Duration) ProviderFactory {
	var mem *memory.Store
	return func(s Settings) (cloud.Provider, error) {
		switch s.Cloud.Provider {
		case ProviderWholeFlow:
			// The business's data API on the WholeFlow server, reached with
			// this PC's key from the activation.
			l := s.Cloud.Link
			switch {
			case l.Revoked:
				return nil, &cloud.Error{Kind: cloud.KindDeviceRevoked, Op: "config", Msg: MsgDeviceRevoked}
			case l.KeyError != "":
				return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "stored PC key cannot be read: " + l.KeyError + "; connect again with a new activation code"}
			case l.BaseURL == "" || l.DeviceKey == "":
				return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "not connected: enter the reference key and activation code on the Cloud Sync page"}
			}
			return rest.New(rest.Config{URL: l.BaseURL, Key: l.DeviceKey,
				BusinessID: s.Business.ID, Timeout: cloudTimeout}, log)
		case ProviderMemory:
			if mem == nil || mem.BusinessID != s.Business.ID {
				mem = memory.New(s.Business.ID)
			}
			return mem, nil
		}
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: fmt.Sprintf("unknown cloud provider %q", s.Cloud.Provider)}
	}
}
