-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Firebase / Google Play services
-keep class com.google.** { *; }
-dontwarn com.google.**
-keep class com.google.firebase.** { *; }

# AppsFlyer
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# WebView JS bridge
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# flutter_local_notifications (uses reflection for scheduling)
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**
