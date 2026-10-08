import Foundation

/// Static provider identities and official website links. Scan/model output never supplies a destination URL.
public enum IntegrationCatalog {
    public struct Entry: Sendable {
        public let id: String
        public let name: String
        public let category: String
        public let website: String
        public let references: [String]
        init(_ id: String, _ name: String, _ category: String, _ website: String, _ references: [String]) {
            self.id = id; self.name = name; self.category = category; self.website = website; self.references = references
        }
    }
    public static let entries: [Entry] = [
        Entry("cloudflare", "Cloudflare", "Hosting", "https://dash.cloudflare.com/", ["wrangler", "@cloudflare/", "cloudflare.com", "workers.dev", "pages.dev"]),
        Entry("vercel", "Vercel", "Hosting", "https://vercel.com/dashboard", ["@vercel/", "vercel.com", "vercel.app", "vercel.json"]),
        Entry("netlify", "Netlify", "Hosting", "https://app.netlify.com/", ["@netlify/", "netlify.com", "netlify.app", "netlify.toml"]),
        Entry("aws", "Amazon Web Services", "Cloud Infrastructure", "https://aws.amazon.com/", ["@aws-sdk/", "aws-sdk", "boto3", "amazonaws.com", "aws-cdk", "AWSSDK", "aws_amplify"]),
        Entry("gcp", "Google Cloud", "Cloud Infrastructure", "https://cloud.google.com/", ["@google-cloud/", "google-cloud-", "cloud.google.com", "google.golang.org/api", "google.cloud."]),
        Entry("azure", "Microsoft Azure", "Cloud Infrastructure", "https://azure.microsoft.com/", ["@azure/", "azure-identity", "azure-storage", "azurewebsites.net", "blob.core.windows.net"]),
        Entry("fly", "Fly.io", "Hosting", "https://fly.io/", ["fly.toml", "fly.io", "fly.dev"]),
        Entry("render", "Render", "Hosting", "https://render.com/", ["render.yaml", "onrender.com"]),
        Entry("railway", "Railway", "Hosting", "https://railway.com/", ["railway.json", "railway.toml", "railway.app", "railway.internal"]),
        Entry("digitalocean", "DigitalOcean", "Cloud Infrastructure", "https://www.digitalocean.com/", ["digitalocean.com", "@digitalocean/", "digitalocean_spaces", "digitaloceanspaces.com"]),
        Entry("heroku", "Heroku", "Hosting", "https://www.heroku.com/", ["heroku.com", "herokuapp.com", "heroku.yml"]),
        Entry("expo", "Expo", "Mobile Builds & Updates", "https://expo.dev/", ["expo", "expo.dev", "expo-updates", "eas.json"]),
        Entry("firebase", "Firebase", "Backend", "https://console.firebase.google.com/", ["firebase", "firebase-admin", "@firebase/", "FirebaseApp", "FirebaseAuth", "FirebaseCore", "firebase.google.com", "firebaseio.com", "firebaseapp.com", "firebase_messaging"]),
        Entry("supabase", "Supabase", "Backend", "https://supabase.com/dashboard", ["@supabase/", "supabase", "supabase.co", "supabase.com"]),
        Entry("neon", "Neon", "Database", "https://console.neon.tech/", ["@neondatabase/", "neon.tech", "neon.database", "neondb"]),
        Entry("planetscale", "PlanetScale", "Database", "https://planetscale.com/", ["@planetscale/", "planetscale.com"]),
        Entry("turso", "Turso", "Database", "https://turso.tech/", ["@libsql/", "libsql-client", "turso.tech", "turso.io"]),
        Entry("mongodb", "MongoDB", "Database", "https://www.mongodb.com/", ["mongodb", "mongoose", "mongodb.net", "MongoSwift"]),
        Entry("upstash", "Upstash", "Database & Messaging", "https://console.upstash.com/", ["@upstash/", "upstash.io", "upstash.com"]),
        Entry("redis", "Redis", "Database", "https://redis.io/", ["redis", "ioredis", "redis-py", "redis.asyncio", "redis.clients", "StackExchange.Redis"]),
        Entry("postgres", "PostgreSQL", "Database", "https://www.postgresql.org/", ["pg", "postgres", "postgresql", "psycopg", "psycopg2", "asyncpg", "org.postgresql"]),
        Entry("mysql", "MySQL", "Database", "https://www.mysql.com/", ["mysql", "mysql2", "pymysql", "mysql-connector", "com.mysql"]),
        Entry("sqlite", "SQLite", "Database", "https://www.sqlite.org/", ["sqlite3", "better-sqlite3", "sqlite", "SQLDelight", "sqflite", "GRDB"]),
        Entry("convex", "Convex", "Backend", "https://dashboard.convex.dev/", ["convex", "convex.dev", "convex.cloud"]),
        Entry("appwrite", "Appwrite", "Backend", "https://appwrite.io/", ["appwrite", "node-appwrite", "appwrite.io"]),
        Entry("sanity", "Sanity", "Content", "https://www.sanity.io/", ["@sanity/", "sanity", "sanity.io"]),
        Entry("contentful", "Contentful", "Content", "https://www.contentful.com/", ["contentful", "contentful.com", "com.contentful"]),
        Entry("wordpress", "WordPress", "Content", "https://wordpress.org/", ["wordpress", "wp-json", "@wordpress/"]),
        Entry("googlesignin", "Google Sign-In", "Authentication", "https://developers.google.com/identity/", ["google-auth-library", "GoogleSignIn", "@react-oauth/google", "passport-google-oauth", "accounts.google.com"]),
        Entry("applesignin", "Sign in with Apple", "Authentication", "https://developer.apple.com/sign-in-with-apple/", ["ASAuthorizationAppleIDProvider", "SignInWithAppleButton", "appleid.apple.com", "sign_in_with_apple"]),
        Entry("appleintelligence", "Apple Intelligence", "On-device AI", "https://developer.apple.com/apple-intelligence/", ["FoundationModels", "SystemLanguageModel", "LanguageModelSession"]),
        Entry("storekit", "StoreKit", "In-App Purchases", "https://developer.apple.com/storekit/", ["StoreKit", "StoreKit2", "in_app_purchase"]),
        Entry("clerk", "Clerk", "Authentication", "https://dashboard.clerk.com/", ["@clerk/", "clerk.com", "clerk.dev", "clerk-sdk"]),
        Entry("auth0", "Auth0", "Authentication", "https://auth0.com/", ["@auth0/", "auth0", "auth0.com"]),
        Entry("betterauth", "Better Auth", "Authentication", "https://www.better-auth.com/", ["better-auth"]),
        Entry("cognito", "Amazon Cognito", "Authentication", "https://aws.amazon.com/cognito/", ["@aws-sdk/client-cognito", "amazon-cognito-identity-js", "cognito-idp", "AWSCognito"]),
        Entry("stripe", "Stripe", "Payments", "https://dashboard.stripe.com/", ["stripe", "@stripe/", "stripe.com", "StripeAPI", "StripePaymentSheet", "com.stripe"]),
        Entry("revenuecat", "RevenueCat", "Payments", "https://app.revenuecat.com/", ["react-native-purchases", "@revenuecat/", "revenuecat.com", "RevenueCat", "purchases_flutter", "com.revenuecat"]),
        Entry("paddle", "Paddle", "Payments", "https://www.paddle.com/", ["@paddle/", "paddle.com", "paddle-python"]),
        Entry("lemonsqueezy", "Lemon Squeezy", "Payments", "https://www.lemonsqueezy.com/", ["@lemonsqueezy/", "lemonsqueezy.com"]),
        Entry("paypal", "PayPal", "Payments", "https://www.paypal.com/", ["@paypal/", "paypal.com", "paypalrestsdk", "PayPalSDK"]),
        Entry("onesignal", "OneSignal", "Notifications", "https://dashboard.onesignal.com/", ["react-native-onesignal", "@onesignal/", "OneSignalFramework", "OneSignal", "onesignal.com", "onesignal_flutter"]),
        Entry("resend", "Resend", "Email", "https://resend.com/", ["resend", "resend.com"]),
        Entry("sendgrid", "SendGrid", "Email", "https://sendgrid.com/", ["@sendgrid/", "sendgrid", "sendgrid.net", "sendgrid.com"]),
        Entry("postmark", "Postmark", "Email", "https://postmarkapp.com/", ["postmark", "postmarkapp.com"]),
        Entry("mailgun", "Mailgun", "Email", "https://www.mailgun.com/", ["mailgun.js", "mailgun-ruby", "mailgun.com", "mailgun.net"]),
        Entry("ses", "Amazon SES", "Email", "https://aws.amazon.com/ses/", ["@aws-sdk/client-ses", "email-smtp", "AWSSES"]),
        Entry("twilio", "Twilio", "Communications", "https://www.twilio.com/", ["twilio", "@twilio/", "twilio.com", "TwilioVoice"]),
        Entry("vonage", "Vonage", "Communications", "https://www.vonage.com/", ["@vonage/", "vonage", "nexmo"]),
        Entry("livekit", "LiveKit", "Communications", "https://livekit.io/", ["livekit-client", "livekit-server-sdk", "@livekit/", "livekit.io", "LiveKit", "livekit.cloud"]),
        Entry("agora", "Agora", "Communications", "https://www.agora.io/", ["agora-rtc-sdk", "agora-rtm-sdk", "agora.io", "AgoraRtcEngine"]),
        Entry("daily", "Daily", "Communications", "https://www.daily.co/", ["@daily-co/", "daily.co"]),
        Entry("vapi", "Vapi", "Communications", "https://vapi.ai/", ["@vapi-ai/", "vapi.ai"]),
        Entry("pusher", "Pusher", "Realtime", "https://pusher.com/", ["pusher", "pusher-js", "pusher.com", "pusher_channels_flutter"]),
        Entry("ably", "Ably", "Realtime", "https://ably.com/", ["ably", "@ably/", "ably.com", "ably.io"]),
        Entry("sentry", "Sentry", "Monitoring", "https://sentry.io/", ["@sentry/", "sentry-sdk", "sentry.io", "Sentry", "sentry_flutter", "io.sentry"]),
        Entry("datadog", "Datadog", "Monitoring", "https://www.datadoghq.com/", ["@datadog/", "datadog", "dd-trace", "datadoghq.com", "DatadogCore"]),
        Entry("newrelic", "New Relic", "Monitoring", "https://newrelic.com/", ["newrelic", "newrelic.com", "com.newrelic"]),
        Entry("bugsnag", "Bugsnag", "Monitoring", "https://www.bugsnag.com/", ["@bugsnag/", "bugsnag", "bugsnag.com"]),
        Entry("posthog", "PostHog", "Analytics", "https://posthog.com/", ["posthog-js", "posthog-node", "posthog-react-native", "posthog.com", "PostHog"]),
        Entry("mixpanel", "Mixpanel", "Analytics", "https://mixpanel.com/", ["mixpanel", "mixpanel-browser", "mixpanel.com", "Mixpanel"]),
        Entry("amplitude", "Amplitude", "Analytics", "https://amplitude.com/", ["@amplitude/", "amplitude-js", "amplitude.com", "AmplitudeSwift"]),
        Entry("plausible", "Plausible", "Analytics", "https://plausible.io/", ["plausible.io", "plausible-tracker"]),
        Entry("analytics", "Google Analytics", "Analytics", "https://analytics.google.com/", ["@google-analytics/", "react-ga4", "react-ga", "google-analytics.com", "analytics.google.com", "gtag(", "gtag.js"]),
        Entry("gtm", "Google Tag Manager", "Analytics", "https://tagmanager.google.com/", ["googletagmanager.com", "react-gtm-module", "google-tag-manager"]),
        Entry("searchconsole", "Search Console", "Search & SEO", "https://search.google.com/search-console/", ["searchconsole", "webmasters/v3", "search.google.com/search-console", "google-site-verification"]),
        Entry("openai", "OpenAI", "AI", "https://platform.openai.com/", ["openai", "@ai-sdk/openai", "api.openai.com", "OpenAIKit"]),
        Entry("anthropic", "Anthropic", "AI", "https://console.anthropic.com/", ["@anthropic-ai/", "@ai-sdk/anthropic", "anthropic", "api.anthropic.com"]),
        Entry("gemini", "Google Gemini", "AI", "https://aistudio.google.com/", ["@google/generative-ai", "@google/genai", "google-generativeai", "google.genai", "generativelanguage.googleapis.com", "@ai-sdk/google"]),
        Entry("elevenlabs", "ElevenLabs", "AI & Audio", "https://elevenlabs.io/", ["@elevenlabs/", "elevenlabs", "api.elevenlabs.io"]),
        Entry("heygen", "HeyGen", "AI & Video", "https://www.heygen.com/", ["@heygen/", "heygen.com"]),
        Entry("fal", "fal", "AI & Media", "https://fal.ai/", ["@fal-ai/", "fal-client", "fal_client", "fal.ai", "fal.run"]),
        Entry("replicate", "Replicate", "AI", "https://replicate.com/", ["replicate", "replicate.com", "@ai-sdk/replicate"]),
        Entry("huggingface", "Hugging Face", "AI", "https://huggingface.co/", ["@huggingface/", "huggingface_hub", "huggingface.co"]),
        Entry("openrouter", "OpenRouter", "AI", "https://openrouter.ai/", ["openrouter.ai", "@openrouter/", "@openrouter/ai-sdk-provider"]),
        Entry("typesafe", "TypeSafe", "AI", "https://typesafe.ai/", ["@typesafe-ai/", "typesafe-sdk", "@typesafe/", "typesafe-api", "typesafe.ai"]),
        Entry("deepgram", "Deepgram", "AI & Audio", "https://deepgram.com/", ["@deepgram/", "deepgram-sdk", "api.deepgram.com"]),
        Entry("assemblyai", "AssemblyAI", "AI & Audio", "https://www.assemblyai.com/", ["assemblyai", "api.assemblyai.com"]),
        Entry("algolia", "Algolia", "Search", "https://www.algolia.com/", ["algoliasearch", "@algolia/", "algolia.net", "algolia.com"]),
        Entry("meilisearch", "Meilisearch", "Search", "https://www.meilisearch.com/", ["meilisearch", "@meilisearch/", "meilisearch.com"]),
        Entry("typesense", "Typesense", "Search", "https://typesense.org/", ["typesense", "typesense.org"]),
        Entry("elasticsearch", "Elasticsearch", "Search", "https://www.elastic.co/", ["@elastic/elasticsearch", "elasticsearch", "elastic.co"]),
        Entry("cloudinary", "Cloudinary", "Media Storage", "https://cloudinary.com/", ["cloudinary", "@cloudinary/", "cloudinary.com"]),
        Entry("uploadthing", "UploadThing", "Storage", "https://uploadthing.com/", ["uploadthing", "@uploadthing/", "uploadthing.com", "utfs.io"]),
        Entry("backblaze", "Backblaze", "Storage", "https://www.backblaze.com/", ["backblazeb2.com", "b2sdk"]),
        Entry("infisical", "Infisical", "Secrets Management", "https://infisical.com/", ["@infisical/", "infisical", "infisical.com"]),
        Entry("onepassword", "1Password", "Secrets Management", "https://1password.com/", ["@1password/", "1password.com", "op://"]),
        Entry("githubactions", "GitHub Actions", "Automation", "https://github.com/features/actions", [".github/workflows/"]),
        Entry("appstore", "App Store Connect", "Distribution", "https://appstoreconnect.apple.com/", ["appstoreconnect.apple.com", "app_store_connect_api_key", "upload_to_app_store", "deliver(", "com.apple.appstoreconnect"]),
        Entry("googleplay", "Google Play", "Distribution", "https://play.google.com/console/", ["androidpublisher", "upload_to_play_store", "play.google.com/console", "com.github.triplet.play"]),
        Entry("testflight", "TestFlight", "Distribution", "https://appstoreconnect.apple.com/", ["upload_to_testflight", "TestFlight", "pilot("]),
        Entry("agentmail", "AgentMail", "Email", "https://www.agentmail.to/", ["agentmail", "agentmail.to"]),
        Entry("zernio", "Zernio", "Social Publishing", "https://zernio.com/", ["zernio.com", "zernio"]),
        Entry("airtable", "Airtable", "Data & Operations", "https://airtable.com/", ["airtable", "airtable.com"]),
        Entry("notion", "Notion", "Data & Operations", "https://www.notion.so/", ["@notionhq/", "notion-client", "api.notion.com"]),
        Entry("slack", "Slack", "Communications", "https://slack.com/", ["@slack/", "slack-sdk", "slack_sdk", "slack.com/api", "hooks.slack.com"]),
        Entry("discord", "Discord", "Communications", "https://discord.com/", ["discord.js", "discord.py", "discord.com/api", "discordapp.com"]),
        Entry("telegram", "Telegram", "Communications", "https://telegram.org/", ["telegraf", "grammy", "python-telegram-bot", "api.telegram.org"]),
        Entry("googlemaps", "Google Maps", "Maps", "https://mapsplatform.google.com/", ["@googlemaps/", "@react-google-maps/", "maps.googleapis.com", "com.google.android.gms:play-services-maps", "GoogleMaps"]),
        Entry("mapbox", "Mapbox", "Maps", "https://www.mapbox.com/", ["mapbox-gl", "@mapbox/", "mapbox.com", "MapboxMaps"]),
        Entry("intercom", "Intercom", "Customer Support", "https://www.intercom.com/", ["intercom-client", "@intercom/", "intercom.io", "intercom.com"]),
        Entry("hubspot", "HubSpot", "CRM", "https://www.hubspot.com/", ["@hubspot/", "hubspot-api-client", "api.hubapi.com", "hubspot.com"]),
        Entry("zendesk", "Zendesk", "Customer Support", "https://www.zendesk.com/", ["node-zendesk", "zendesk.com", "@zendesk/"]),
        Entry("customerio", "Customer.io", "Messaging", "https://customer.io/", ["customerio-node", "customer.io", "CustomerIO"]),
        Entry("shopify", "Shopify", "Commerce", "https://www.shopify.com/", ["@shopify/", "shopify_api", "myshopify.com", "shopify.com"]),
        Entry("mentionwell", "MentionWell", "Content", "https://mentionwell.com/", ["mentionwell.com", "@mentionwell/"]),
        Entry("hotlyne", "HotLyne", "Customer Support", "https://hotlyne.com/", ["hotlyne.com", "@hotlyne/"])
    ]
    public static func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }
    private static let patterns: [String: NSRegularExpression] = {
        var result: [String: NSRegularExpression] = [:]
        for reference in Set(entries.flatMap(\.references)) {
            let escaped = NSRegularExpression.escapedPattern(for: reference)
            let end = reference.hasSuffix("/") || reference.hasSuffix("(") || reference.hasSuffix(".") ? "" : "(?![A-Za-z0-9_-])"
            result[reference] = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_-])" + escaped + end, options: .caseInsensitive)
        }
        return result
    }()
    public static func matches(_ reference: String, in text: String) -> Range<String.Index>? {
        guard let pattern = patterns[reference], let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return Range(match.range, in: text)
    }
}
