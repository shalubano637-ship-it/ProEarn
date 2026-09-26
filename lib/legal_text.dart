// =============================================================================
// PRO EARN — Legal text (Terms & Conditions, Privacy Policy)
// -----------------------------------------------------------------------------
// Single source of truth. Previously this exact text was duplicated inline
// in both auth_screen.dart and user_profile_features.dart — they drifted
// apart over time (the auth_screen copy correctly said "Supabase", the
// user_profile_features copy still said "Google Firebase Authentication and
// Firestore DB" from before the Supabase migration). Both files now import
// and display these constants instead of holding their own copy, so there
// is only ever one place to update.
//
// NOTE: this is in-app text only, not a substitute for a publicly hosted
// privacy policy page — Play Console requires a public URL in the store
// listing, separate from this in-app display.
//
// Monetization section reflects the AdMob-rewarded-ad revenue-share model
// (40% of real rewarded-ad revenue, split by completions) — update the
// percentage/threshold here if those numbers change, and nowhere else.
// =============================================================================

const String kTermsAndConditionsText = '''
PRO EARN - TERMS AND CONDITIONS
Last Updated: August 2026

Welcome to PRO EARN ("App"). By downloading, installing, or registering an account, you strictly agree to comply with the following terms.

1. REGISTRATION AND SECURITY
- You must provide accurate registration details (Username, Email).
- Users are limited to ONE account per individual. Mass creation or pipeline automated accounts will result in immediate termination.

2. PROHIBITION OF NUDITY AND EXPLICIT SEXUAL CONTENT
- PRO EARN maintains a ZERO-TOLERANCE policy for sexually explicit material.
- You are STRICTLY PROHIBITED from uploading, creating, or sharing any media displaying pornography, nudity, semi-nudity, sexual acts, highly suggestive underwear/lingerie depictions, or any form of sexually explicit text node pipelines.
- All uploads undergo automated classification layers (Google Cloud Vision API). Any trigger matching 'Adult', 'Racy', or 'Sexually Suggestive' classification scales results in immediate structural suppression of the post.
- Severe or repeat violations will trigger an irreversible device-level hardware hash BAN and absolute termination of your wallet parameters.

3. MONETIZATION & COINS
- Pro Earn uses an in-app virtual coin system. Coins have no cash value, cannot be exchanged for real money, cryptocurrency, or gift cards, and are not a financial product.
- Eligible engagement (post "Gets") earns Bonus Coins at a fixed rate shown in the app.
- Bonus Coins can be claimed into your Main Balance once you cross the minimum threshold shown in the app. Claiming is an in-app transfer only — no bank account, UPI ID, or payment method is involved.
- Engagement manipulation through scripts, bot rings, or coordinated farms will result in immediate coin forfeiture.

4. ADS POLICY & USER ENGAGEMENT
- Interacting with Ad environments using deceptive methods, clicking advertisements systematically to manipulate monetization mechanics, or using automated script triggers violates Google AdMob/Ad Policies. Detected infringements trigger instant suspension.
''';

const String kPrivacyPolicyText = '''
PRO EARN - PRIVACY POLICY
Last Updated: August 2026

PRO EARN values your privacy ecosystem. This document explains transparently what data we process and map within our system data models.

1. INFORMATION WE COLLECT
- Account Identifiers: Email, encrypted passwords, and custom user-generated Usernames stored securely inside our Supabase (Postgres) database and Auth system.
- Profile Parameters: Custom Bios, links, and profile image tracking URLs processed via secure cloud storage endpoints.
- Engagement Telemetry: Trackers on Follower/Following indexes, like maps, share counts, comment text nodes, and analytical 'Gets' score structures.

2. CONTENT MODERATION AND INAPPROPRIATE MATERIAL PROCESSING
- To strictly comply with Google Play Developer Policies regarding User Generated Content (UGC), all uploaded media is continuously processed through the Google Cloud Vision Annotation Engine.
- This automated assessment specifically filters for visual markers indicating explicit nudity, physical exploitation, and adult content themes.
- Metadata and classification flags generated during safety reviews are mapped explicitly onto your account parameters to protect the safe community standards of the application ecosystem.

3. GOOGLE ADMOB NETWORK TRACES
- This app operates using Google Mobile Ads infrastructure. These frameworks process standard behavioral identifiers and device-state parameters to serve tailored banner/interstitial/rewarded ad content.

4. USER RIGHTS & RETENTION ARCHITECTURES
- If you request a full account purge, you can initiate data collection deletions via our email support endpoint: proearn.in@gmail.com.
''';
