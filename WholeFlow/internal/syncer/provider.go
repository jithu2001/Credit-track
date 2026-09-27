package syncer

import (
	"fmt"
	"log/slog"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/cloud/memory"
	"wholeflow/internal/cloud/supabase"
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
		case ProviderSupabase:
			if s.Cloud.KeyError != "" {
				return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "stored Supabase key cannot be read: " + s.Cloud.KeyError}
			}
			return supabase.New(supabase.Config{URL: s.Cloud.SupabaseURL, ServiceRoleKey: s.Cloud.SupabaseKey,
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
