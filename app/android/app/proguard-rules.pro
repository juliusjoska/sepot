# Šepot — R8/ProGuard pravidla pro release.
#
# Cíl: zapnout shrink/optimalizaci (menší APK), ale nechat žít nativní
# a reflexí volané třídy, které R8 jinak ořeže a app spadne za běhu.

# --- Flutter jádro ---
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# --- libsignal (Rust FFI přes JNI) — názvy tříd drží nativní vrstva ---
-keep class org.signal.** { *; }
-keep class org.whispersystems.** { *; }

# --- flutter_local_notifications (desugaring, Gson modely) ---
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# --- Firebase / FCM (opt-in fast mode) ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# --- Tink (crypto z flutter_secure_storage) ---
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# --- UnifiedPush ---
-keep class org.unifiedpush.** { *; }

# Zachovej nativní metody (JNI vazby)
-keepclasseswithmembernames class * {
    native <methods>;
}
