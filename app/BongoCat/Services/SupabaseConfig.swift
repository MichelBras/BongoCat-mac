import Foundation

/**
 * Supabase Configuration for BongoCat
 *
 * Setup Instructions:
 * 1. Create a Supabase project at https://supabase.com
 * 2. Get your Project URL and anon key from Project Settings > API
 * 3. Configure your credentials (choose one method):
 *
 *    Option A - Environment Variables (Recommended for CI/CD):
 *    export SUPABASE_URL="https://your-project.supabase.co"
 *    export SUPABASE_ANON_KEY="your-anon-key-here"
 *
 *    Option B - Local Config File (Recommended for local development):
 *    cp app/supabase-config.plist.template app/BongoCat/supabase-config.plist
 *    # Edit supabase-config.plist with your keys (gitignored)
 *
 *    Option C - Info.plist (Not recommended for public repos):
 *    Add SUPABASE_URL and SUPABASE_ANON_KEY keys to Info.plist
 */
struct SupabaseConfig {
    let url: String
    let anonKey: String
    let source: String

    /// Attempts to load Supabase credentials from environment → plist → Info.plist.
    /// Returns nil if no valid credentials are found (app runs in offline-only mode).
    static func load() -> SupabaseConfig? {
        // 1. Environment variables (preferred for CI/CD and scripted builds)
        if let url = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !url.isEmpty, url != "YOUR_SUPABASE_URL",
           !key.isEmpty {
            return SupabaseConfig(url: url, anonKey: key, source: "environment variables")
        }

        // 2. Local supabase-config.plist (gitignored, safe for dev)
        if let configPath = Bundle.main.path(forResource: "supabase-config", ofType: "plist"),
           let configDict = NSDictionary(contentsOfFile: configPath),
           let url = configDict["SUPABASE_URL"] as? String,
           let key = configDict["SUPABASE_ANON_KEY"] as? String,
           !url.isEmpty, url != "YOUR_SUPABASE_URL",
           !key.isEmpty {
            return SupabaseConfig(url: url, anonKey: key, source: "supabase-config.plist")
        }

        // Note: Info.plist fallback intentionally omitted — credentials embedded in the
        // app binary are extractable via reverse engineering. Use env vars or the plist file.

        return nil
    }
}
