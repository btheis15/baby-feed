import Foundation

/// Where the app syncs. Fill these in from Supabase → Project Settings → API.
/// The publishable (anon) key is safe to ship: row-level security protects the data.
/// Leave the placeholders and the app runs local-only.
enum SupabaseConfig {
    static let urlString = "https://YOUR-PROJECT-REF.supabase.co"
    static let anonKey = "YOUR-PUBLISHABLE-KEY"

    static var isConfigured: Bool {
        !urlString.contains("YOUR-PROJECT") && !anonKey.contains("YOUR-") && URL(string: urlString) != nil
    }

    static var url: URL { URL(string: urlString)! }
}
